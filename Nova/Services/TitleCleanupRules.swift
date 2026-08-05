//
//  TitleCleanupRules.swift
//  Nova
//
//  User-editable regular-expression rules for cleaning up messy filenames into nice
//  display titles. Each rule carries a plain-language description so the list reads
//  like documentation, not raw regex. Rules are applied in order, after the built-in
//  normalization, and sync across devices via iCloud key-value storage.
//

import Foundation
import Combine

/// A single find/replace rule with a human description.
struct TitleCleanupRule: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    /// What this rule does, in plain language (shown in the UI).
    var ruleDescription: String
    /// The regular-expression pattern to match.
    var pattern: String
    /// The replacement template (supports $1, $2 capture references). Often empty.
    var replacement: String
    /// Case-insensitive matching.
    var caseInsensitive: Bool = true
    /// Whether the rule is currently applied.
    var isEnabled: Bool = true

    /// Applies this rule to a string, returning the input unchanged if the pattern
    /// is invalid so a bad rule can never crash cleanup.
    func apply(to input: String) -> String {
        guard isEnabled, !pattern.isEmpty else { return input }
        var options: NSRegularExpression.Options = []
        if caseInsensitive { options.insert(.caseInsensitive) }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return input
        }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.stringByReplacingMatches(in: input, options: [], range: range,
                                              withTemplate: replacement)
    }

    /// True if the pattern compiles.
    var isValid: Bool {
        (try? NSRegularExpression(pattern: pattern)) != nil
    }
}

/// A helpful starter set covering the most common release-name junk. Declared at file
/// scope (not on the actor-isolated store) so both the store and the nonisolated
/// snapshot can reference it from any context.
private func defaultCleanupRules() -> [TitleCleanupRule] {
    [
        TitleCleanupRule(ruleDescription: "Remove resolution tags like 1080p, 720p, 2160p, 4K",
                         pattern: #"\b(2160p|1080p|720p|480p|4k)\b"#, replacement: ""),
        TitleCleanupRule(ruleDescription: "Remove source tags like BluRay, WEB-DL, HDRip, WEBRip",
                         pattern: #"\b(bluray|blu-ray|web-?dl|webrip|hdrip|dvdrip|brrip|hdtv)\b"#, replacement: ""),
        TitleCleanupRule(ruleDescription: "Remove codec and audio tags like x264, x265, HEVC, DDP5.1, AAC",
                         pattern: #"\b(x264|x265|h\.?264|h\.?265|hevc|ddp?5\.1|dts|aac|ac3|atmos|truehd)\b"#, replacement: ""),
        TitleCleanupRule(ruleDescription: "Remove anything in brackets or braces, like [group] or {info}",
                         pattern: #"[\[\{][^\]\}]*[\]\}]"#, replacement: ""),
        TitleCleanupRule(ruleDescription: "Remove a trailing release-group tag after a dash (e.g. -RARBG)",
                         pattern: #"-\s*[A-Za-z0-9]+\s*$"#, replacement: ""),
        TitleCleanupRule(ruleDescription: "Collapse multiple spaces into one",
                         pattern: #"\s{2,}"#, replacement: " "),
    ]
}

@MainActor
final class TitleCleanupRulesStore: ObservableObject {
    static let shared = TitleCleanupRulesStore()

    @Published var rules: [TitleCleanupRule] {
        didSet { persist(); TitleCleanupRulesStore.snapshot = rules }
    }

    /// A plain-array snapshot of the rules, kept in sync so non-actor code (like
    /// MetadataParser.cleanTitle) can apply them without hopping actors.
    nonisolated(unsafe) static var snapshot: [TitleCleanupRule] = defaultCleanupRules()

    /// The starter rule set. Nonisolated so it's reachable from any context.
    nonisolated static var defaults: [TitleCleanupRule] { defaultCleanupRules() }

    /// Applies the current snapshot rules in order. Safe to call from anywhere.
    nonisolated static func applySnapshot(to input: String) -> String {
        var result = input
        for rule in snapshot where rule.isEnabled {
            result = rule.apply(to: result)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private let key = "title.cleanup.rules.v1"
    private var isApplyingRemote = false
    private var cancellable: AnyCancellable?

    private init() {
        if let data = CloudSync.shared.data(forKey: key) ?? UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([TitleCleanupRule].self, from: data),
           !decoded.isEmpty {
            rules = decoded
        } else {
            rules = defaultCleanupRules()
        }
        TitleCleanupRulesStore.snapshot = rules

        cancellable = CloudSync.shared.externalChange
            .receive(on: RunLoop.main)
            .sink { [weak self] changedKeys in
                guard let self, changedKeys.contains(self.key) else { return }
                guard let data = CloudSync.shared.data(forKey: self.key),
                      let decoded = try? JSONDecoder().decode([TitleCleanupRule].self, from: data)
                else { return }
                self.isApplyingRemote = true
                self.rules = decoded
                self.isApplyingRemote = false
            }
    }

    /// Runs the enabled rules in order over an already space-normalized title.
    func clean(_ input: String) -> String {
        var result = input
        for rule in rules where rule.isEnabled {
            result = rule.apply(to: result)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func add(_ rule: TitleCleanupRule) { rules.append(rule) }
    func remove(_ id: UUID) { rules.removeAll { $0.id == id } }
    func move(from: IndexSet, to: Int) { rules.move(fromOffsets: from, toOffset: to) }
    func resetToDefaults() { rules = defaultCleanupRules() }

    private func persist() {
        guard !isApplyingRemote else { return }
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: key)
            CloudSync.shared.setData(data, forKey: key)
            CloudSync.shared.flush()
        }
    }
}
