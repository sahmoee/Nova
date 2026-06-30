//
//  ShowSettingsStore.swift
//  FrameTV
//
//  Per-show ("binge") settings. Each series can override the global autoplay and
//  skip behavior, so you can, say, auto-play and skip intros for one show but be
//  asked before the next episode on another.
//
//  Keyed by a series key (the series title lowercased, matching how episodes group).
//  Persisted as JSON; small and local.
//

import Foundation

/// Per-show overrides. `nil` on an option means "use the global default."
struct ShowSettings: Codable, Hashable {
    var autoPlayNext: Bool?
    var skipIntro: Bool?
    var skipCredits: Bool?
    var askBeforeNext: Bool?

    static let inherit = ShowSettings(autoPlayNext: nil, skipIntro: nil, skipCredits: nil, askBeforeNext: nil)
}

@MainActor
final class ShowSettingsStore: ObservableObject {
    @Published private(set) var byShow: [String: ShowSettings] = [:]

    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        fileURL = support.appendingPathComponent("show_settings.json")
        load()
    }

    /// Normalizes a series title into a stable key.
    static func key(forSeries title: String) -> String {
        title.trimmingCharacters(in: .whitespaces).lowercased()
    }

    func settings(forSeries title: String) -> ShowSettings {
        byShow[Self.key(forSeries: title)] ?? .inherit
    }

    func update(_ settings: ShowSettings, forSeries title: String) {
        let key = Self.key(forSeries: title)
        if settings == .inherit {
            byShow.removeValue(forKey: key)
        } else {
            byShow[key] = settings
        }
        persist()
    }

    /// Resolves an effective value for a show, falling back to the global default.
    func autoPlayNext(forSeries title: String, default global: Bool) -> Bool {
        settings(forSeries: title).autoPlayNext ?? global
    }
    func skipIntro(forSeries title: String, default global: Bool) -> Bool {
        settings(forSeries: title).skipIntro ?? global
    }
    func skipCredits(forSeries title: String, default global: Bool) -> Bool {
        settings(forSeries: title).skipCredits ?? global
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: ShowSettings].self, from: data)
        else { return }
        byShow = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(byShow) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
