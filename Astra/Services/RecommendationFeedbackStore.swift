//
//  RecommendationFeedbackStore.swift
//  Astra
//
//  Remembers the user's "not for me" signals so recommendations improve over time:
//    • Not Interested / Hide  -> the title is hidden from Discover & Home rec rows,
//      and its genres are down-weighted.
//    • More Like This         -> its genres are up-weighted so similar titles surface.
//    • Already Watched        -> hidden from recommendations (seen elsewhere).
//
//  Keyed by ContentID.stableKey so it works for catalog items that aren't in the
//  library. Persisted to UserDefaults, mirrored to iCloud KVS, reloaded after a
//  backup restore, and included in the backup snapshot.
//

import Foundation
import Combine

@MainActor
final class RecommendationFeedbackStore: ObservableObject {
    static let shared = RecommendationFeedbackStore()

    /// Titles the user hid ("Not Interested") — removed from recommendations.
    @Published private(set) var hiddenKeys: Set<String> = []
    /// Titles marked "Already watched elsewhere" — also removed from recommendations.
    @Published private(set) var watchedKeys: Set<String> = []
    /// Per-genre preference score. Positive = liked (More Like This), negative =
    /// disliked (Not Interested). Used to bias ranking.
    @Published private(set) var genreScores: [String: Int] = [:]

    private let defaultsKey = "reco.feedback.v1"
    static let cloudKey = "cloud.reco.feedback.v1"
    private let defaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()

    private struct Snapshot: Codable {
        var hidden: [String]
        var watched: [String]
        var genres: [String: Int]
    }

    private init() {
        load()
        CloudSync.shared.externalChange
            .receive(on: RunLoop.main)
            .sink { [weak self] keys in
                if keys.contains(Self.cloudKey) { self?.load() }
            }
            .store(in: &cancellables)
        NotificationCenter.default.addObserver(
            forName: .astraBackupRestored, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.load() }
        }
    }

    // MARK: - Queries

    /// Whether a title should be excluded from recommendations.
    func isSuppressed(_ key: String) -> Bool {
        hiddenKeys.contains(key) || watchedKeys.contains(key)
    }

    /// A ranking bias for a set of genres (sum of their scores). Higher = surface more.
    func genreBias(for genres: [String]) -> Int {
        genres.reduce(0) { $0 + (genreScores[$1.lowercased()] ?? 0) }
    }

    /// Removes suppressed items and returns the rest, stable order preserved. `key`
    /// extracts a stableKey from each element.
    func visible<T>(_ items: [T], key: (T) -> String) -> [T] {
        items.filter { !isSuppressed(key($0)) }
    }

    // MARK: - Actions

    /// "Not Interested": hide the title and down-weight its genres.
    func notInterested(key: String, genres: [String]) {
        hiddenKeys.insert(key)
        for g in genres { adjustGenre(g, by: -1) }
        persist()
    }

    /// "More Like This": up-weight the title's genres (and un-hide it if hidden).
    func moreLikeThis(genres: [String]) {
        for g in genres { adjustGenre(g, by: +2) }
        persist()
    }

    /// "Already watched elsewhere": remove from recommendations without changing taste.
    func alreadyWatched(key: String) {
        watchedKeys.insert(key)
        persist()
    }

    /// Un-hide a single title (undo).
    func unhide(key: String) {
        hiddenKeys.remove(key)
        watchedKeys.remove(key)
        persist()
    }

    /// Clears all recommendation feedback.
    func reset() {
        hiddenKeys = []
        watchedKeys = []
        genreScores = [:]
        persist()
    }

    var hasFeedback: Bool {
        !hiddenKeys.isEmpty || !watchedKeys.isEmpty || !genreScores.isEmpty
    }

    // MARK: - Internals

    private func adjustGenre(_ genre: String, by delta: Int) {
        let g = genre.lowercased()
        // Clamp so a single genre can't dominate ranking.
        genreScores[g] = max(-5, min(5, (genreScores[g] ?? 0) + delta))
        if genreScores[g] == 0 { genreScores[g] = nil }
    }

    private func load() {
        // Prefer the iCloud copy if present; fall back to local.
        let data = CloudSync.shared.data(forKey: Self.cloudKey) ?? defaults.data(forKey: defaultsKey)
        guard let data, let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        hiddenKeys = Set(snap.hidden)
        watchedKeys = Set(snap.watched)
        genreScores = snap.genres
    }

    private func persist() {
        let snap = Snapshot(hidden: Array(hiddenKeys), watched: Array(watchedKeys), genres: genreScores)
        guard let data = try? JSONEncoder().encode(snap) else { return }
        defaults.set(data, forKey: defaultsKey)
        CloudSync.shared.setData(data, forKey: Self.cloudKey)
    }
}
