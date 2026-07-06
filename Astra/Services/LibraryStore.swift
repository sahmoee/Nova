//
//  LibraryStore.swift
//  Astra
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
        loadQueue()
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
            AstraLog.sync.error("Library too large to sync to iCloud (\(data.count) bytes)")
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
            // Index the freshly loaded library into Spotlight (no-op on tvOS).
            SpotlightIndexer.reindex(items)
            // Seed the widget snapshot on launch (no-op effect on tvOS).
            writeWidgetSnapshot()
        } catch {
            // Corrupt/old format: start clean rather than crash.
            items = []
        }
    }

    // MARK: - Duplicate detection & merge

    /// A group of library items that appear to be the same title from different
    /// sources (matched by shared imdb/tmdb id, or by normalized title + year).
    struct DuplicateGroup: Identifiable {
        let id = UUID()
        let items: [MediaItem]
        var title: String { items.first?.title ?? "" }
    }

    /// Finds groups of likely-duplicate items. Only movies/standalone titles are
    /// grouped (episodes are matched precisely by contentKey already). A group needs
    /// at least two items.
    func duplicateGroups() -> [DuplicateGroup] {
        // Only consider non-episode items (episodes dedupe exactly by contentKey).
        let candidates = items.filter { $0.episode == nil }
        var buckets: [String: [MediaItem]] = [:]
        for item in candidates {
            buckets[duplicateKey(for: item), default: []].append(item)
        }
        return buckets.values
            .filter { $0.count > 1 }
            .map { DuplicateGroup(items: $0.sorted { $0.addedDate < $1.addedDate }) }
            .sorted { $0.title.lowercased() < $1.title.lowercased() }
    }

    /// A loose identity key for duplicate matching: prefer a shared imdb/tmdb id,
    /// otherwise normalized title + year.
    private func duplicateKey(for item: MediaItem) -> String {
        if let imdb = item.contentID?.imdb { return "imdb:\(imdb)" }
        if let tmdb = item.contentID?.tmdb { return "tmdb:\(tmdb)" }
        let title = item.title.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
        let year = item.metadata.year.map(String.init) ?? "?"
        return "title:\(title):\(year)"
    }

    /// Merges a duplicate group into a single item: keeps the most-complete record
    /// (most progress / has artwork), unions favorite status and the furthest watch
    /// progress, repoints any collections to the survivor, and removes the rest.
    func mergeDuplicates(_ group: DuplicateGroup) {
        guard group.items.count > 1 else { return }
        // Choose a survivor: prefer one with a contentID, then artwork, then most progress.
        let survivor = group.items.max { a, b in
            score(a) < score(b)
        } ?? group.items[0]

        guard let sIdx = items.firstIndex(where: { $0.id == survivor.id }) else { return }

        // Merge state from the others into the survivor.
        var merged = items[sIdx]
        for other in group.items where other.id != survivor.id {
            merged.isFavorite = merged.isFavorite || other.isFavorite
            if other.lastPlayedPosition > merged.lastPlayedPosition {
                merged.lastPlayedPosition = other.lastPlayedPosition
                merged.lastPlayedDate = other.lastPlayedDate ?? merged.lastPlayedDate
            }
            if merged.duration == nil { merged.duration = other.duration }
            if merged.posterURL == nil { merged.posterURL = other.posterURL }
            if merged.backdropURL == nil { merged.backdropURL = other.backdropURL }
            merged.addedDate = min(merged.addedDate, other.addedDate)
        }
        items[sIdx] = merged

        // Repoint collections from any removed content keys to the survivor's key.
        let survivorKey = merged.contentKey
        let removedKeys = group.items.filter { $0.id != survivor.id }.map { $0.contentKey }
        for cIdx in collections.indices {
            var changed = false
            collections[cIdx].contentKeys = collections[cIdx].contentKeys.map { key in
                if removedKeys.contains(key) { changed = true; return survivorKey }
                return key
            }
            // De-dupe keys after repointing.
            if changed {
                var seen = Set<String>()
                collections[cIdx].contentKeys = collections[cIdx].contentKeys.filter { seen.insert($0).inserted }
            }
        }
        persistCollections()

        // Remove the merged-away items.
        let removeIDs = Set(group.items.filter { $0.id != survivor.id }.map { $0.id })
        items.removeAll { removeIDs.contains($0.id) }
        persist()
    }

    /// Merges every detected duplicate group at once.
    func mergeAllDuplicates() {
        for group in duplicateGroups() { mergeDuplicates(group) }
    }

    /// Completeness score for choosing a merge survivor.
    private func score(_ item: MediaItem) -> Int {
        var s = 0
        if item.contentID != nil { s += 100 }
        if item.posterURL != nil { s += 20 }
        if item.lastPlayedPosition > 0 { s += 10 }
        if item.isFavorite { s += 5 }
        return s
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
        // Keep iOS Spotlight in sync with the current library (no-op on tvOS).
        SpotlightIndexer.reindex(items)
        // Refresh the widget snapshot (iOS widgets read this; harmless on tvOS).
        writeWidgetSnapshot()
    }

    /// Builds and stores the compact snapshot the iOS widget reads from the shared
    /// App Group container, and asks WidgetKit to refresh.
    private func writeWidgetSnapshot() {
        func entry(_ item: MediaItem) -> WidgetEntry {
            let isShow = item.contentID?.type == .series
            let subtitle: String
            if let ep = item.episode {
                subtitle = "S\(ep.season) E\(ep.number)"
            } else {
                var parts = [isShow ? "Show" : "Movie"]
                if let y = item.metadata.year { parts.append(String(y)) }
                subtitle = parts.joined(separator: " · ")
            }
            let key = item.contentID?.stableKey ?? item.contentKey
            let link = "frametv://\(isShow ? "show" : "movie")/\(key)"
            return WidgetEntry(
                id: item.contentKey,
                title: item.seriesTitle ?? item.title,
                subtitle: subtitle,
                posterURLString: item.posterURL?.absoluteString,
                progress: item.progressFraction,
                deepLink: link
            )
        }
        let snapshot = WidgetSnapshot(
            continueWatching: continueWatching.prefix(8).map(entry),
            recentlyAdded: recentlyAdded.prefix(8).map(entry),
            updated: Date()
        )
        WidgetShared.write(snapshot)
        WidgetRefresher.reload()
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

    // MARK: - Tags, hiding, subtitle offset (Batch B/C)

    /// Hide or unhide an item from the main library view.
    func toggleHidden(_ item: MediaItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].isHidden.toggle()
        persist()
    }

    func setHidden(_ hidden: Bool, for ids: Set<UUID>) {
        for id in ids {
            if let idx = items.firstIndex(where: { $0.id == id }) { items[idx].isHidden = hidden }
        }
        persist()
    }

    /// Add a tag (case-insensitive de-dupe) to an item.
    func addTag(_ tag: String, to item: MediaItem) {
        let clean = tag.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        if !items[idx].tags.contains(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) {
            items[idx].tags.append(clean)
            persist()
        }
    }

    func removeTag(_ tag: String, from item: MediaItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
        persist()
    }

    /// Apply a tag to many items at once (bulk edit).
    func addTag(_ tag: String, to ids: Set<UUID>) {
        let clean = tag.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        for id in ids {
            if let idx = items.firstIndex(where: { $0.id == id }),
               !items[idx].tags.contains(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) {
                items[idx].tags.append(clean)
            }
        }
        persist()
    }

    /// Every distinct tag used across the library, sorted.
    var allTags: [String] {
        var set = Set<String>()
        var ordered: [String] = []
        for item in items {
            for tag in item.tags where !set.contains(tag.lowercased()) {
                set.insert(tag.lowercased()); ordered.append(tag)
            }
        }
        return ordered.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Remember a subtitle timing offset (seconds) for an item.
    func setSubtitleOffset(_ offset: Double, for item: MediaItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].subtitleOffset = offset
        persist()
    }

    /// Bulk favorite/unfavorite.
    func setFavorite(_ favorite: Bool, for ids: Set<UUID>) {
        for id in ids {
            if let idx = items.firstIndex(where: { $0.id == id }) { items[idx].isFavorite = favorite }
        }
        persist()
    }

    /// Bulk remove.
    func remove(ids: Set<UUID>) {
        items.removeAll { ids.contains($0.id) }
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

    /// Marks an item as fully watched (sets progress to complete) and stamps the date.
    func markWatched(_ item: MediaItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        if let d = items[idx].duration, d > 0 {
            items[idx].lastPlayedPosition = d
        } else {
            // No known duration: use a sentinel so isWatched (>=90%) is satisfied.
            items[idx].duration = 100
            items[idx].lastPlayedPosition = 100
        }
        items[idx].lastPlayedDate = Date()
        // Queue means "plan to watch" — once watched, it leaves the queue.
        if queueIDs.contains(items[idx].id) {
            queueIDs.removeAll { $0 == items[idx].id }
            persistQueue()
        }
        persist()
    }

    /// Marks an item as unwatched (clears progress and last-played date).
    func markUnwatched(_ item: MediaItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].lastPlayedPosition = 0
        items[idx].lastPlayedDate = nil
        persist()
    }

    // MARK: - Watchlist Queue
    //
    // A dedicated "I plan to watch this" list, separate from Favorites ("I like
    // this"). Stored as an ordered list of item IDs, persisted locally and synced
    // via iCloud KVS so the queue follows the user across iPhone, iPad, and tvOS.

    @Published private(set) var queueIDs: [UUID] = []

    private var queueDefaultsKey: String { "library.queue.v1" }

    /// Loads the queue from local storage (called from init via loadQueue()).
    func loadQueue() {
        if let data = UserDefaults.standard.data(forKey: queueDefaultsKey),
           let ids = try? JSONDecoder().decode([UUID].self, from: data) {
            queueIDs = ids
        }
        // Adopt a cloud copy if one exists (newer device wins on merge below).
        if let data = CloudSync.shared.data(forKey: queueDefaultsKey),
           let ids = try? JSONDecoder().decode([UUID].self, from: data),
           !ids.isEmpty, queueIDs.isEmpty {
            queueIDs = ids
        }
    }

    private func persistQueue() {
        if let data = try? JSONEncoder().encode(queueIDs) {
            UserDefaults.standard.set(data, forKey: queueDefaultsKey)
            CloudSync.shared.setData(data, forKey: queueDefaultsKey)
        }
    }

    /// Whether an item is currently in the queue.
    func isQueued(_ item: MediaItem) -> Bool { queueIDs.contains(item.id) }

    /// Adds an item to the end of the queue (no duplicates).
    func addToQueue(_ item: MediaItem) {
        guard !queueIDs.contains(item.id) else { return }
        queueIDs.append(item.id)
        persistQueue()
    }

    func removeFromQueue(_ item: MediaItem) {
        queueIDs.removeAll { $0 == item.id }
        persistQueue()
    }

    /// Reorders the queue (list-style move).
    func moveInQueue(from source: IndexSet, to destination: Int) {
        queueIDs.move(fromOffsets: source, toOffset: destination)
        persistQueue()
    }

    /// The queued items in order, skipping any that were removed from the library.
    var queuedItems: [MediaItem] {
        queueIDs.compactMap { id in items.first(where: { $0.id == id }) }
    }

    /// The next thing to watch tonight: the first queued item, preferring one that is
    /// already in progress so an unfinished pick surfaces first.
    var upNextInQueue: MediaItem? {
        queuedItems.first(where: { $0.hasResumePoint }) ?? queuedItems.first
    }

    /// Items that have been watched or partially played, most recent first — powers a
    /// "Recently Watched" rail.
    var recentlyWatched: [MediaItem] {
        items
            .filter { $0.lastPlayedDate != nil }
            .sorted { ($0.lastPlayedDate ?? .distantPast) > ($1.lastPlayedDate ?? .distantPast) }
    }

    // MARK: - Queries (used by Home/Library rows)

    var favorites: [MediaItem] {
        collapseToShow(items.filter { $0.isFavorite })
    }

    var continueWatching: [MediaItem] {
        items
            .filter { $0.hasResumePoint }
            .sorted { ($0.lastPlayedDate ?? .distantPast) > ($1.lastPlayedDate ?? .distantPast) }
    }

    var recentlyAdded: [MediaItem] {
        collapseToShow(items.sorted { $0.addedDate > $1.addedDate })
    }

    /// Collapses episodes so each series appears once (its most recent episode
    /// represents the whole show), while movies and non-episodic items stay
    /// individual. Used by Home rows so a show isn't listed once per episode.
    func collapseToShow(_ input: [MediaItem]) -> [MediaItem] {
        var seenShows = Set<String>()
        var result: [MediaItem] = []
        for item in input {
            if item.isSeries {
                let showKey = item.seriesTitle?.lowercased()
                    ?? item.contentID?.stableKey
                    ?? item.title.lowercased()
                if seenShows.insert(showKey).inserted { result.append(item) }
            } else {
                result.append(item)
            }
        }
        return result
    }

    /// The library grid's entries: standalone movies as-is, but episodes collapsed so
    /// each series-season shows a single entry (represented by its most recently added
    /// episode) instead of one card per episode. Sorted by most recently added.
    var libraryEntries: [MediaItem] {
        let sorted = items.sorted { $0.addedDate > $1.addedDate }
        var seenSeasonKeys = Set<String>()
        var movieSlots: [String: Int] = [:]
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
                // Movies: never show the same title twice. Prefer a real content ID,
                // falling back to normalized title + year. The recently played copy wins.
                let key: String
                if let raw = item.contentID?.stableKey, !raw.hasPrefix("unknown:") {
                    key = raw
                } else {
                    let year = item.metadata.year.map(String.init) ?? ""
                    key = "movie:\(item.title.lowercased())|\(year)"
                }
                if let slot = movieSlots[key] {
                    if prefersForDedupe(item, over: result[slot]) { result[slot] = item }
                } else {
                    movieSlots[key] = result.count
                    result.append(item)
                }
            }
        }
        return result
    }

    /// True when candidate should represent the deduped entry: the more recently
    /// played copy wins; then playback progress; otherwise the newest addition stays.
    private func prefersForDedupe(_ candidate: MediaItem, over current: MediaItem) -> Bool {
        switch (candidate.lastPlayedDate, current.lastPlayedDate) {
        case let (c?, e?): return c > e
        case (.some, .none): return true
        case (.none, .some): return false
        case (.none, .none):
            return candidate.lastPlayedPosition > 0 && current.lastPlayedPosition == 0
        }
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

    /// Marks a specific episode watched or unwatched, if it exists in the library.
    /// Episodes not yet in the library (never played) can't be marked; returns
    /// whether a matching item was found.
    @discardableResult
    func setEpisodeWatched(_ watched: Bool, imdb: String?, tmdb: Int?, season: Int, number: Int) -> Bool {
        guard let ep = episodeItem(imdb: imdb, tmdb: tmdb, season: season, number: number) else { return false }
        if watched { markWatched(ep) } else { markUnwatched(ep) }
        return true
    }
}
