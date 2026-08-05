//
//  StreamHistoryStore.swift
//  Nova
//
//  Remembers the exact stream a user last played for a given movie or episode, plus
//  when they played it. This powers two things:
//
//    • Resume reuses the previous stream — instead of re-running auto-select (which
//      might pick a different source), resuming re-resolves the same StreamOption.
//    • The stream picker marks that stream ("Used 6 hrs ago", "Used 2 min ago") and
//      floats it to the top so it's a one-tap continue.
//
//  StreamOption is Codable and carries the addon + url/infohash needed to re-resolve
//  a fresh playable link, so a stored choice stays usable even after debrid/addon
//  links expire. Entries are keyed by content (per-episode for series) and persisted
//  to UserDefaults, mirrored to iCloud KVS so history follows the user across devices.
//

import Foundation
import Combine

/// One remembered playback choice.
struct StreamHistoryEntry: Codable, Hashable {
    var stream: StreamOption
    var lastUsed: Date
}

@MainActor
final class StreamHistoryStore: ObservableObject {
    static let shared = StreamHistoryStore()

    private let defaultsKey = "stream.history.v1"
    static let cloudKey = "cloud.stream.history.v1"

    /// contentKey -> entry. Published so the picker updates live.
    @Published private(set) var entries: [String: StreamHistoryEntry] = [:]

    private let defaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()

    private init() {
        load()
        mergeFromCloud()

        CloudSync.shared.externalChange
            .receive(on: RunLoop.main)
            .sink { [weak self] keys in
                if keys.contains(Self.cloudKey) { self?.mergeFromCloud() }
            }
            .store(in: &cancellables)

        // Reload after a backup restore writes the history blob.
        NotificationCenter.default.addObserver(
            forName: .novaBackupRestored, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.load(); self?.mergeFromCloud() }
        }
    }

    // MARK: - Keys

    /// The history key for a movie or a specific episode.
    static func key(catalogKey: String, episode: EpisodeRef?) -> String {
        if let episode {
            return "\(catalogKey):s\(episode.season)e\(episode.number)"
        }
        return catalogKey
    }

    // MARK: - Public API

    /// The remembered stream for a movie/episode, if any.
    func entry(catalogKey: String, episode: EpisodeRef?) -> StreamHistoryEntry? {
        entries[Self.key(catalogKey: catalogKey, episode: episode)]
    }

    /// Record (or refresh) the stream the user just played.
    func record(_ stream: StreamOption, catalogKey: String, episode: EpisodeRef?) {
        let k = Self.key(catalogKey: catalogKey, episode: episode)
        entries[k] = StreamHistoryEntry(stream: stream, lastUsed: Date())
        persist()
    }

    /// Whether a given stream id matches the remembered choice for this content.
    func isPrevious(_ streamID: String, catalogKey: String, episode: EpisodeRef?) -> Bool {
        entry(catalogKey: catalogKey, episode: episode)?.stream.id == streamID
    }

    /// A short relative-time string like "Used 6 hrs ago", "Used 2 min ago".
    static func usedAgoText(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        let text: String
        switch seconds {
        case ..<60:
            let s = Int(seconds)
            text = s <= 1 ? "just now" : "\(s) sec ago"
        case ..<3600:
            let m = Int(seconds / 60)
            text = "\(m) min ago"
        case ..<86_400:
            let h = Int(seconds / 3600)
            text = "\(h) hr\(h == 1 ? "" : "s") ago"
        case ..<604_800:
            let d = Int(seconds / 86_400)
            text = "\(d) day\(d == 1 ? "" : "s") ago"
        case ..<2_592_000:
            let w = Int(seconds / 604_800)
            text = "\(w) week\(w == 1 ? "" : "s") ago"
        case ..<31_536_000:
            let mo = Int(seconds / 2_592_000)
            text = "\(mo) month\(mo == 1 ? "" : "s") ago"
        default:
            let y = Int(seconds / 31_536_000)
            text = "\(y) year\(y == 1 ? "" : "s") ago"
        }
        return text == "just now" ? "Used just now" : "Used \(text)"
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: StreamHistoryEntry].self, from: data) else { return }
        entries = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: defaultsKey)
        CloudSync.shared.setData(data, forKey: Self.cloudKey)
    }

    /// Adopt the iCloud copy, merging by most-recent-per-key so no device's history
    /// is lost when two devices played different things.
    private func mergeFromCloud() {
        guard let data = CloudSync.shared.data(forKey: Self.cloudKey),
              let cloud = try? JSONDecoder().decode([String: StreamHistoryEntry].self, from: data) else { return }
        var merged = entries
        for (k, v) in cloud {
            if let local = merged[k] {
                if v.lastUsed > local.lastUsed { merged[k] = v }
            } else {
                merged[k] = v
            }
        }
        if merged != entries {
            entries = merged
            if let encoded = try? JSONEncoder().encode(entries) {
                defaults.set(encoded, forKey: defaultsKey)
            }
        }
    }
}
