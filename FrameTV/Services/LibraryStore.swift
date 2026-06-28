//
//  LibraryStore.swift
//  FrameTV
//
//  Owns the unified media library. Persists to a local Codable JSON file in
//  Application Support. (SwiftData can replace this later behind the same API.)
//
//  Marked @MainActor because it publishes UI state.
//

import Foundation
import Combine

@MainActor
final class LibraryStore: ObservableObject {

    @Published private(set) var items: [MediaItem] = []

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(filename: String = "library.json") {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        // Ensure the directory exists.
        try? FileManager.default.createDirectory(
            at: support, withIntermediateDirectories: true
        )
        self.fileURL = support.appendingPathComponent(filename)

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        load()
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            items = []
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try decoder.decode([MediaItem].self, from: data)
            // One-time cleanup: collapse duplicates (same content saved multiple
            // times before dedup-by-contentKey existed), keeping the first.
            var seen = Set<String>()
            var deduped: [MediaItem] = []
            for item in decoded where seen.insert(item.contentKey).inserted {
                deduped.append(item)
            }
            // Remove the old seeded sample items (Google sample-video bucket) that the
            // user never favorited or started watching, so the library isn't filled
            // with placeholder rows that have no real artwork.
            let cleaned = deduped.filter { item in
                let isSample = item.playbackURL.absoluteString.contains("gtv-videos-bucket")
                let engaged = item.isFavorite || item.lastPlayedPosition > 0 || item.lastPlayedDate != nil
                return !(isSample && !engaged)
            }
            items = cleaned
            if cleaned.count != decoded.count { persist() }
        } catch {
            // Corrupt/old format: start clean rather than crash.
            items = []
        }
    }

    private func persist() {
        do {
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Persistence failure shouldn't crash the UI; surface elsewhere if needed.
        }
    }

    // MARK: - CRUD

    func add(_ item: MediaItem) {
        // Dedupe by stable content identity, not the per-playback random id, so
        // replaying the same episode updates its entry instead of adding a copy.
        if let idx = items.firstIndex(where: { $0.contentKey == item.contentKey }) {
            // Preserve the existing id, favorite flag, and added date; refresh the rest.
            var updated = item
            updated.id = items[idx].id
            updated.isFavorite = items[idx].isFavorite
            updated.addedDate = items[idx].addedDate
            items[idx] = updated
        } else {
            items.insert(item, at: 0)
        }
        persist()
    }

    func update(_ item: MediaItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx] = item
        persist()
    }

    func remove(_ item: MediaItem) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        persist()
    }

    func toggleFavorite(_ item: MediaItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].isFavorite.toggle()
        persist()
    }

    func clearAll() {
        items.removeAll()
        persist()
    }

    /// Resets only watch progress across the whole library.
    func clearWatchHistory() {
        for idx in items.indices {
            items[idx].lastPlayedPosition = 0
            items[idx].lastPlayedDate = nil
        }
        persist()
    }

    /// Removes a single item from Continue Watching by resetting its progress.
    func clearProgress(for id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].lastPlayedPosition = 0
        items[idx].lastPlayedDate = nil
        persist()
    }

    /// Clears everything from Continue Watching at once.
    func clearContinueWatching() {
        for idx in items.indices where items[idx].hasResumePoint {
            items[idx].lastPlayedPosition = 0
            items[idx].lastPlayedDate = nil
        }
        persist()
    }

    // MARK: - Queries (used by Home/Library rows)

    var favorites: [MediaItem] {
        items.filter { $0.isFavorite }
    }

    var continueWatching: [MediaItem] {
        items
            .filter { $0.hasResumePoint }
            .sorted { ($0.lastPlayedDate ?? .distantPast) > ($1.lastPlayedDate ?? .distantPast) }
    }

    var recentlyAdded: [MediaItem] {
        items.sorted { $0.addedDate > $1.addedDate }
    }

    /// The library grid's entries: standalone movies as-is, but episodes collapsed so
    /// each series-season shows a single entry (represented by its most recently added
    /// episode) instead of one card per episode. Sorted by most recently added.
    var libraryEntries: [MediaItem] {
        let sorted = items.sorted { $0.addedDate > $1.addedDate }
        var seenSeasonKeys = Set<String>()
        var result: [MediaItem] = []
        for item in sorted {
            if let ep = item.episode {
                // Group key: series identity + season number.
                let seriesKey = item.seriesTitle?.lowercased()
                    ?? item.contentID?.stableKey
                    ?? item.title.lowercased()
                let key = "\(seriesKey)|s\(ep.season)"
                if seenSeasonKeys.insert(key).inserted {
                    result.append(item)   // first (most recent) episode represents the season
                }
            } else {
                result.append(item)       // movies and non-episodic content stay individual
            }
        }
        return result
    }

    func items(for source: SourceType) -> [MediaItem] {
        items.filter { $0.sourceType == source }
    }

    func item(id: UUID) -> MediaItem? {
        items.first { $0.id == id }
    }

    /// Finds a library item matching a series (by IMDB/TMDB id) and a specific
    /// season+episode, if one has been played before.
    func episodeItem(imdb: String?, tmdb: Int?, season: Int, number: Int) -> MediaItem? {
        items.first { item in
            guard let ep = item.episode, ep.season == season, ep.number == number else { return false }
            if let imdb, item.contentID?.imdb == imdb { return true }
            if let tmdb, item.contentID?.tmdb == tmdb { return true }
            return false
        }
    }

    /// Whether a specific episode has been watched (>= 90%).
    func isEpisodeWatched(imdb: String?, tmdb: Int?, season: Int, number: Int) -> Bool {
        episodeItem(imdb: imdb, tmdb: tmdb, season: season, number: number)?.isWatched ?? false
    }

    /// Whether a specific episode is partially watched (has a resume point).
    func isEpisodeInProgress(imdb: String?, tmdb: Int?, season: Int, number: Int) -> Bool {
        episodeItem(imdb: imdb, tmdb: tmdb, season: season, number: number)?.hasResumePoint ?? false
    }
}
