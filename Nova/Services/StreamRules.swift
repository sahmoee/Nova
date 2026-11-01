//
//  StreamRules.swift
//  Nova
//
//  User stream rules, Nova's take on Omni's regex patterns. Each rule matches text
//  in a stream's name, title, filename or addon and then tags it with a color,
//  prefers or avoids it in ranking, hides it, or marks it as an auto-play pick.
//  Matching is plain case-insensitive text by default; regex is opt-in, length
//  bounded and validated before it is saved.
//

import Foundation
import Combine

struct StreamRule: Codable, Hashable, Identifiable, Sendable {
    enum Effect: String, Codable, CaseIterable, Identifiable, Sendable {
        case tag, prefer, avoid, hide
        var id: String { rawValue }
        var title: String {
            switch self {
            case .tag:    return "Tag Only"
            case .prefer: return "Prefer"
            case .avoid:  return "Avoid"
            case .hide:   return "Hide"
            }
        }
    }

    /// Fixed palette so tags stay legible on the black canvas.
    enum TagColor: String, Codable, CaseIterable, Identifiable, Sendable {
        case violet, blue, teal, green, yellow, orange, red, gray
        var id: String { rawValue }
    }

    var id: UUID = UUID()
    var name: String
    var pattern: String
    var isRegex: Bool = false
    var effect: Effect = .tag
    var color: TagColor = .violet
    /// When any enabled rule has this on, auto-select picks among its matches first.
    var autoPlay: Bool = false
    var isEnabled: Bool = true

    static let maxPatternLength = 200
    static let maxRules = 100
}

/// Pure matching and scoring. Rules are compiled once per evaluation batch.
struct StreamRuleEngine: Sendable {
    private struct Compiled: Sendable {
        let rule: StreamRule
        let regex: NSRegularExpression?
    }

    private let compiled: [Compiled]

    init(rules: [StreamRule]) {
        compiled = rules.compactMap { rule in
            guard rule.isEnabled, StreamRuleEngine.validationError(for: rule) == nil else { return nil }
            let regex = rule.isRegex
                ? try? NSRegularExpression(pattern: rule.pattern, options: [.caseInsensitive])
                : nil
            if rule.isRegex && regex == nil { return nil }
            return Compiled(rule: rule, regex: regex)
        }
    }

    var isEmpty: Bool { compiled.isEmpty }
    var hasAutoPlayRules: Bool { compiled.contains { $0.rule.autoPlay } }

    /// Why a rule can't be saved, or nil when it is valid.
    static func validationError(for rule: StreamRule) -> String? {
        let trimmed = rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Enter text to match." }
        if rule.pattern.count > StreamRule.maxPatternLength {
            return "Patterns are limited to \(StreamRule.maxPatternLength) characters."
        }
        if rule.isRegex, (try? NSRegularExpression(pattern: rule.pattern, options: [.caseInsensitive])) == nil {
            return "This regular expression isn't valid."
        }
        return nil
    }

    /// Text a rule is matched against.
    static func haystack(for stream: StreamOption) -> String {
        [stream.name, stream.rawTitle, stream.behaviorHints?.filename, stream.addonName]
            .compactMap { $0 }
            .joined(separator: "\n")
    }

    /// Rules that match a stream, in the user's order.
    func matches(_ stream: StreamOption) -> [StreamRule] {
        matches(text: StreamRuleEngine.haystack(for: stream))
    }

    func matches(text: String) -> [StreamRule] {
        compiled.filter { entry in
            if let regex = entry.regex {
                let range = NSRange(text.startIndex..., in: text)
                return regex.firstMatch(in: text, options: [], range: range) != nil
            }
            return text.range(of: entry.rule.pattern, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        .map(\.rule)
    }

    /// Ranking adjustment: prefer and avoid outweigh resolution but not availability.
    func scoreAdjustment(for stream: StreamOption) -> Int {
        matches(stream).reduce(0) { total, rule in
            switch rule.effect {
            case .prefer: return total + 350
            case .avoid:  return total - 350
            case .tag, .hide: return total
            }
        }
    }

    func isHidden(_ stream: StreamOption) -> Bool {
        matches(stream).contains { $0.effect == .hide }
    }

    func isAutoPlayPick(_ stream: StreamOption) -> Bool {
        matches(stream).contains { $0.autoPlay && $0.effect != .hide && $0.effect != .avoid }
    }
}

/// Persists the user's rules locally and offers bounded JSON import/export.
@MainActor
final class StreamRuleStore: ObservableObject {
    static let shared = StreamRuleStore()

    @Published var rules: [StreamRule] { didSet { persist() } }

    private let defaults: UserDefaults
    private static let key = "streamRules.v1"
    static let maxImportBytes = 64 * 1024

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([StreamRule].self, from: data) {
            rules = Array(decoded.prefix(StreamRule.maxRules))
        } else {
            rules = []
        }
    }

    var engine: StreamRuleEngine { StreamRuleEngine(rules: rules) }

    func upsert(_ rule: StreamRule) {
        if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[idx] = rule
        } else if rules.count < StreamRule.maxRules {
            rules.append(rule)
        }
    }

    func delete(_ id: UUID) { rules.removeAll { $0.id == id } }

    func move(id: UUID, offset: Int) {
        guard let idx = rules.firstIndex(where: { $0.id == id }) else { return }
        let target = idx + offset
        guard rules.indices.contains(target) else { return }
        rules.swapAt(idx, target)
    }

    func exportJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(rules)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    enum ImportError: LocalizedError {
        case tooLarge, unreadable, empty
        var errorDescription: String? {
            switch self {
            case .tooLarge:   return "That file is larger than 64 KB."
            case .unreadable: return "That isn't a Nova stream rules file."
            case .empty:      return "No valid rules were found."
            }
        }
    }

    /// Parses rules without applying them, so Settings can preview first. Invalid
    /// rules are dropped and every imported rule gets a fresh identity.
    static func parseImport(_ text: String) throws -> [StreamRule] {
        guard let data = text.data(using: .utf8) else { throw ImportError.unreadable }
        guard data.count <= maxImportBytes else { throw ImportError.tooLarge }
        guard let decoded = try? JSONDecoder().decode([StreamRule].self, from: data) else {
            throw ImportError.unreadable
        }
        let valid = decoded.prefix(StreamRule.maxRules).compactMap { rule -> StreamRule? in
            guard StreamRuleEngine.validationError(for: rule) == nil else { return nil }
            var copy = rule
            copy.id = UUID()
            copy.name = String(rule.name.prefix(60))
            return copy
        }
        guard !valid.isEmpty else { throw ImportError.empty }
        return valid
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
