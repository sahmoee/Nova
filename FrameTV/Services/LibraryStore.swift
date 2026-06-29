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
    @Published private(set) var collections: [MediaCollection] = []

    private let fileURL: URL
    private let collectionsURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    // iCloud sync. The library is mirrored to iCloud KVS so favorites, watch
    // progress, and saved items follow the user across iPhone, iPad, and Apple TV.
    private let cloudKey = "cloud.library.v1"
    private let cloudRevisionKey = "cloud.library.revision"
    private var cancellables = Set<AnyCancellable>()
    /// Guards against echoing a remote change straight back to iCloud.
    private var applyingRemoteChange = false

    init(filename: String = "library.json") {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        // Ensure the directory exists.
        try? FileManager.default.createDirectory(
            at: support, withIntermediateDirectories: true
        )
        self.fileURL = support.appendingPathComponent(filename)
        self.collectionsURL = support.appendingPathComponent("collections.json")

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        load()
        loadCollections()
        startCloudSync()
    }

    // MARK: - iCloud sync

    private func startCloudSync() {
        // Adopt a newer cloud copy at launch (e.g. changes made on another device
        // while this one was closed).
        mergeFromCloudIfNewer()

        // React to live changes pushed from other devices.
        CloudSync.shared.externalChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] keys in
                guard let self else { return }
                if keys.contains(self.cloudKey) || keys.contains(self.cloudRevisionKey) {
                    self.mergeFromCloudIfNewer()
                }
            }
            .store(in: &cancellables)
    }

    /// Loads the library from iCloud if its revision is newer than what we last saw,
    /// then publishes it. Uses a monotonically increasing revision so the most recent
    /// write wins and devices converge.
    private func mergeFromCloudIfNewer() {
        guard let data = CloudSync.shared.data(forKey: cloudKey),
              let decoded = try? decoder.decode([MediaItem].self, from: data) else { return }

        let cloudRev = CloudSync.shared.double(forKey: cloudRevisionKey) ?? 0
        let localRev = UserDefaults.standard.double(forKey: cloudRevisionKey)
        // Only adopt if the cloud copy is at least as new, and actually differs.
        guard cloudRev >= localRev else { return }

        applyingRemoteChange = true
        items = decoded
        UserDefaults.standard.set(cloudRev, forKey: cloudRevisionKey)
        // Write through to the local file so an offline launch still has the latest.
        persistLocalOnly()
        applyingRemoteChange = false
    }

    /// Pushes the current library to iCloud with a fresh revision stamp.
    private func pushToCloud() {
        guard !applyingRemoteChange else { return }
        guard let data = try? encoder.encode(items) else { return }
        // Skip if the payload exceeds iCloud KVS's per-value limit (~1MB); the local
        // file still holds everything, we just can't mirror an oversized library.
        guard data.count < 900_000 else {
            FrameLog.sync.error("Library too large to sync to iCloud (\(data.count) bytes)")
            return
        }
        let rev = Date().timeIntervalSince1970
        UserDefaults.standard.set(rev, forKey: cloudRevisionKey)
        CloudSync.shared.setData(data, forKey: cloudKey)
        CloudSync.shared.setDouble(rev, forKey: cloudRevisionKey)
        CloudSync.shared.flush()
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

    // MARK: - Collections

    private let collectionsCloudKey = "cloud.collections.v1"

    private func loadCollections() {
        // Prefer local file; fall back to iCloud if present and local is empty.
        if let data = try? Data(contentsOf: collectionsURL),
           let decoded = try? decoder.decode([MediaCollection].self, from: data) {
            collections = decoded
        } else if let json = CloudSync.shared.string(forKey: collectionsCloudKey),
                  let data = json.data(using: .utf8),
                  let decoded = try? decoder.decode([MediaCollection].self, from: data) {
            collections = decoded
        }
    }

    private func persistCollections() {
        if let data = try? encoder.encode(collections) {
            try? data.write(to: collectionsURL, options: [.atomic])
            if let json = String(data: data, encoding: .utf8) {
                CloudSync.shared.setString(json, forKey: collectionsCloudKey)
            }
        }
    }

    /// Creates a new empty collection and returns it.
    @discardableResult
    func createCollection(name: String, systemImage: String = "rectangle.stack") -> MediaCollection {
        let collection = MediaCollection(name: name, systemImage: systemImage)
        collections.append(collection)
        persistCollections()
        return collection
    }

    func renameCollection(_ id: UUID, to name: String) {
        guard let idx = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[idx].name = name
        persistCollections()
    }

    func deleteCollection(_ id: UUID) {
        collections.removeAll { $0.id == id }
        persistCollections()
    }

    /// Adds an item to a collection (no-op if already present).
    func addToCollection(_ collectionID: UUID, item: MediaItem) {
        guard let idx = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        if !collections[idx].contentKeys.contains(item.contentKey) {
            collections[idx].contentKeys.append(item.contentKey)
            persistCollections()
        }
    }

    func removeFromCollection(_ collectionID: UUID, contentKey: String) {
        guard let idx = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        collections[idx].contentKeys.removeAll { $0 == contentKey }
        persistCollections()
    }

    /// Whether an item is in a given collection.
    func isInCollection(_ collectionID: UUID, item: MediaItem) -> Bool {
        collections.first(where: { $0.id == collectionID })?
            .contentKeys.contains(item.contentKey) ?? false
    }

    /// The library items that belong to a collection, in collection order.
    func items(in collection: MediaCollection) -> [MediaItem] {
        collection.contentKeys.compactMap { key in
            items.first(where: { $0.contentKey == key })
        }
    }

    // MARK: - Persistence

    private func persist() {
        persistLocalOnly()
        pushToCloud()
    }

    /// Writes only the local file, without touching iCloud (used when applying a
    /// change that came *from* iCloud, to avoid an echo).
    private func persistLocalOnly() {
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
