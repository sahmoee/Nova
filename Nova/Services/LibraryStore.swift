//
//  LibraryStore.swift
//  Nova
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
    @Published private(set) var lastPersistenceError: String?

    private let defaults: UserDefaults
    private let fileURL: URL
    private let collectionsURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var durableItems: [MediaItem] = []
    private var libraryNeedsRecovery = false
    #if os(iOS)
    var allowsWatchEdits: Bool { !libraryNeedsRecovery }
    #endif
    private var collectionsNeedRecovery = false

    // iCloud sync. The library is mirrored to iCloud KVS so favorites, watch
    // progress, and saved items follow the user across iPhone, iPad, and Apple TV.
    private let cloudKey = PrefKey.cloudLibrary
    private let cloudRevisionKey = PrefKey.cloudLibraryRevision
    private var cancellables = Set<AnyCancellable>()
    /// Guards against echoing a remote change straight back to iCloud.
    private var applyingRemoteChange = false

    init(filename: String = "library.json", directory: URL? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let support = directory ?? FileManager.default
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
                if keys.contains(self.cloudKey) || keys.contains(self.cloudRevisionKey)
                    || keys.contains(SettingsDataDomain.library.deletionKey)
                    || keys.contains(SettingsDataDomain.history.deletionKey) {
                    self.mergeFromCloudIfNewer()
                }
            }
            .store(in: &cancellables)
    }

    /// Loads the library from iCloud if its revision is newer than what we last saw,
    /// then publishes it. Uses a monotonically increasing revision so the most recent
    /// write wins and devices converge.
    @discardableResult
    private func mergeFromCloudIfNewer(force: Bool = false) -> Bool {
        applySettingsDeletions()
        // Progress lives inside the library payload. A device-only history reset
        // must suspend both directions until the user explicitly resumes sync.
        guard !CloudSync.shared.isPaused(.history), (!libraryNeedsRecovery || force) else { return false }
        guard let data = CloudSync.shared.data(forKey: cloudKey),
              data.count <= LibraryFilePolicy.maximumLibraryBytes,
              var decoded = try? decoder.decode([MediaItem].self, from: data) else { return false }
        let historyDeletion = CloudSync.shared.deletionDate(.history)
        for index in decoded.indices where historyDeletion > 0
            && (decoded[index].lastPlayedDate?.timeIntervalSince1970 ?? 0) <= historyDeletion {
            decoded[index].lastPlayedPosition = 0
            decoded[index].lastPlayedDate = nil
        }

        let cloudRev = CloudSync.shared.double(forKey: cloudRevisionKey) ?? 0
        let localRev = defaults.double(forKey: cloudRevisionKey)
        // Only adopt if the cloud copy is at least as new, and actually differs.
        // FIX: the "actually differs" half was never enforced, so every KVS
        // notification republished the whole library (invalidating all observing
        // views) and rewrote the local file even when nothing changed.
        guard cloudRev.isFinite, cloudRev >= 0, (force || cloudRev >= localRev), (decoded != items || force) else { return false }
        // Publish a remote snapshot only after it is durable locally. Cancel the
        // pending local echo before accepting its revision.
        do {
            try LibraryFilePolicy.write(try encoder.encode(decoded), to: fileURL,
                                        maximumBytes: LibraryFilePolicy.maximumLibraryBytes)
        } catch {
            lastPersistenceError = error.localizedDescription
            return false
        }
        cloudPushTask?.cancel()
        libraryNeedsRecovery = false
        lastPersistenceError = nil

        applyingRemoteChange = true
        items = decoded
        durableItems = decoded
        defaults.set(cloudRev, forKey: cloudRevisionKey)
        applyingRemoteChange = false
        SpotlightIndexer.reindex(items)
        writeWidgetSnapshot()
        return true
    }

    /// Pushes the current library to iCloud with a fresh revision stamp.
    private var cloudPushTask: Task<Void, Never>?

    /// Debounced: a burst of mutations (bulk tag, merge, import) collapses into a
    /// single iCloud write ~0.6s after the last change. Local persistence is
    /// unaffected — persistLocalOnly() still runs immediately on every mutation.
    private func pushToCloud() {
        guard !applyingRemoteChange else { return }
        cloudPushTask?.cancel()
        cloudPushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.pushToCloudNow()
        }
    }

    private func pushToCloudNow() {
        guard !applyingRemoteChange, !libraryNeedsRecovery, !CloudSync.shared.isPaused(.history) else { return }
        guard let data = try? encoder.encode(items) else { return }
        // Skip if the payload exceeds iCloud KVS's per-value limit (~1MB); the local
        // file still holds everything, we just can't mirror an oversized library.
        guard data.count < 900_000 else {
            NovaLog.sync.error("Library too large to sync to iCloud (\(data.count) bytes)")
            return
        }
        let rev = Date().timeIntervalSince1970
        defaults.set(rev, forKey: cloudRevisionKey)
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
            let data = try LibraryFilePolicy.read(fileURL, maximumBytes: LibraryFilePolicy.maximumLibraryBytes)
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
            durableItems = cleaned
            if cleaned.count != decoded.count { persist() }
            // Index the freshly loaded library into Spotlight (no-op on tvOS).
            SpotlightIndexer.reindex(items)
            // Seed the widget snapshot on launch (no-op effect on tvOS).
            writeWidgetSnapshot()
        } catch {
            // Keep unreadable user data intact; ordinary mutations must never
            // overwrite it with the empty recovery view.
            libraryNeedsRecovery = true
            lastPersistenceError = error.localizedDescription
            items = []
        }
    }

    // MARK: - Collections

    private let collectionsCloudKey = PrefKey.cloudCollections

    private func loadCollections() {
        if FileManager.default.fileExists(atPath: collectionsURL.path) {
            do {
                let data = try LibraryFilePolicy.read(collectionsURL, maximumBytes: LibraryFilePolicy.maximumCollectionsBytes)
                collections = try decoder.decode([MediaCollection].self, from: data)
            } catch {
                collectionsNeedRecovery = true
                lastPersistenceError = error.localizedDescription
            }
            return
        }
        if let json = CloudSync.shared.string(forKey: collectionsCloudKey),
           let data = json.data(using: .utf8), data.count <= LibraryFilePolicy.maximumCollectionsBytes,
           let decoded = try? decoder.decode([MediaCollection].self, from: data) {
            _ = persistCollections(decoded)
        }
    }

    @discardableResult
    private func persistCollections(_ candidate: [MediaCollection]? = nil) -> Bool {
        do {
            guard !collectionsNeedRecovery else { throw LibraryFilePolicy.Failure.recoveryRequired }
            let value = candidate ?? collections
            let data = try encoder.encode(value)
            try LibraryFilePolicy.write(data, to: collectionsURL, maximumBytes: LibraryFilePolicy.maximumCollectionsBytes)
            if value != collections { collections = value }
            if let json = String(data: data, encoding: .utf8) {
                CloudSync.shared.setString(json, forKey: collectionsCloudKey)
            }
            if !libraryNeedsRecovery { lastPersistenceError = nil }
            return true
        } catch {
            lastPersistenceError = error.localizedDescription
            return false
        }
    }

    /// Creates a new empty collection and returns it.
    @discardableResult
    func createCollection(name: String, systemImage: String = "rectangle.stack") -> MediaCollection? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let collection = MediaCollection(name: name, systemImage: systemImage)
        return persistCollections(collections + [collection]) ? collection : nil
    }

    func renameCollection(_ id: UUID, to name: String) {
        guard let idx = collections.firstIndex(where: { $0.id == id }) else { return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, collections[idx].name != name else { return }
        var candidate = collections
        candidate[idx].name = name
        _ = persistCollections(candidate)
    }

    func deleteCollection(_ id: UUID) {
        let candidate = collections.filter { $0.id != id }
        guard candidate != collections else { return }
        _ = persistCollections(candidate)
    }

    /// Adds an item to a collection (no-op if already present).
    func addToCollection(_ collectionID: UUID, item: MediaItem) {
        guard let idx = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        if !collections[idx].contentKeys.contains(item.contentKey) {
            var candidate = collections
            candidate[idx].contentKeys.append(item.contentKey)
            _ = persistCollections(candidate)
        }
    }

    /// Bulk counterpart used by list imports. It preserves collection order while
    /// collapsing duplicates, and persists once regardless of list size.
    func addToCollection(_ collectionID: UUID, items newItems: [MediaItem]) {
        guard let idx = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        var candidate = collections
        var seen = Set(candidate[idx].contentKeys)
        var changed = false
        for item in newItems where seen.insert(item.contentKey).inserted {
            candidate[idx].contentKeys.append(item.contentKey)
            changed = true
        }
        if changed { _ = persistCollections(candidate) }
    }

    func removeFromCollection(_ collectionID: UUID, contentKey: String) {
        guard let idx = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        var candidate = collections
        candidate[idx].contentKeys.removeAll { $0 == contentKey }
        guard candidate != collections else { return }
        _ = persistCollections(candidate)
    }

    /// Whether an item is in a given collection.
    func isInCollection(_ collectionID: UUID, item: MediaItem) -> Bool {
        collections.first(where: { $0.id == collectionID })?
            .contentKeys.contains(item.contentKey) ?? false
    }

    /// The library items that belong to a collection, in collection order.
    func items(in collection: MediaCollection) -> [MediaItem] {
        LibraryMutationPolicy.orderedValues(keys: collection.contentKeys, values: items, key: \.contentKey)
    }

    // MARK: - Persistence

    private func persist() {
        guard persistLocalOnly() else {
            cloudPushTask?.cancel()
            if items != durableItems { items = durableItems }
            return
        }
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
            let link = "nova://\(isShow ? "show" : "movie")/\(key)"
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
    @discardableResult
    private func persistLocalOnly() -> Bool {
        do {
            guard !libraryNeedsRecovery else { throw LibraryFilePolicy.Failure.recoveryRequired }
            let data = try encoder.encode(items)
            try LibraryFilePolicy.write(data, to: fileURL, maximumBytes: LibraryFilePolicy.maximumLibraryBytes)
            durableItems = items
            if !collectionsNeedRecovery { lastPersistenceError = nil }
            return true
        } catch {
            lastPersistenceError = error.localizedDescription
            return false
        }
    }

    // MARK: - CRUD

    func add(_ item: MediaItem) {
        merge(item)
        persist()
    }

    /// Imports a list with one local/iCloud publication instead of rewriting the
    /// library for every title. `merge` retains the same durable watch state as add().
    func add(contentsOf newItems: [MediaItem]) {
        guard !newItems.isEmpty else { return }
        let candidate = LibraryMutationPolicy.adding(newItems, to: items)
        guard candidate != items else { return }
        items = candidate
        persist()
    }

    /// Atomically replaces the portion of the index owned by one media server.
    /// User state survives through `merge`, while titles removed from that server
    /// disappear without touching SMB, direct-link, addon, or other-server rows.
    @discardableResult
    func reconcileMediaServer(_ newItems: [MediaItem], connectionID: UUID) -> Bool {
        guard newItems.allSatisfy({ $0.metadata.mediaServerID == connectionID && $0.metadata.mediaServerItemID?.isEmpty == false }) else { return false }
        guard !libraryNeedsRecovery else {
            lastPersistenceError = LibraryFilePolicy.Failure.recoveryRequired.localizedDescription
            return false
        }
        let result = LibraryMutationPolicy.reconcile(newItems, existing: items, connectionID: connectionID)
        guard result.items != items else { return true }
        let remapped = LibraryMutationPolicy.remapping(collections, keys: result.renamedKeys)
        return commitLibraryChange(result.items, collections: remapped, queue: queueIDs)
    }

    /// Bridge references before replacing the independent files. On failure, keep
    /// the old published state and restore the original references where writable.
    private func commitLibraryChange(_ candidate: [MediaItem], collections nextCollections: [MediaCollection], queue nextQueue: [UUID]) -> Bool {
        guard !libraryNeedsRecovery else {
            lastPersistenceError = LibraryFilePolicy.Failure.recoveryRequired.localizedDescription
            return false
        }
        let oldCollections = collections, oldQueue = queueIDs
        let nextByID = Dictionary(nextCollections.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var bridge = collections
        for index in bridge.indices {
            if let next = nextByID[bridge[index].id] {
                bridge[index].contentKeys = LibraryMutationPolicy.unique(bridge[index].contentKeys + next.contentKeys)
            }
        }
        if nextCollections != collections {
            // Even an unchanged bridge must be writable before records disappear.
            guard persistCollections(bridge) else { return false }
        }
        let queueBridge = LibraryMutationPolicy.unique(queueIDs + nextQueue)
        if queueBridge != queueIDs { queueIDs = queueBridge; persistQueue() }
        do {
            try LibraryFilePolicy.write(try encoder.encode(candidate), to: fileURL,
                                        maximumBytes: LibraryFilePolicy.maximumLibraryBytes)
        } catch {
            cloudPushTask?.cancel()
            if collections != oldCollections { _ = persistCollections(oldCollections) }
            if queueIDs != oldQueue { queueIDs = oldQueue; persistQueue() }
            lastPersistenceError = error.localizedDescription
            return false
        }
        items = candidate
        durableItems = candidate
        if nextQueue != queueIDs { queueIDs = nextQueue; persistQueue() }
        let referencesSaved = nextCollections == collections || persistCollections(nextCollections)
        if referencesSaved && !collectionsNeedRecovery { lastPersistenceError = nil }
        pushToCloud()
        SpotlightIndexer.reindex(items)
        writeWidgetSnapshot()
        return referencesSaved
    }

    private func merge(_ item: MediaItem) {
        if let idx = items.firstIndex(where: { $0.contentKey == item.contentKey }) {
            let updated = LibraryMutationPolicy.merged(item, preserving: items[idx])
            if updated != items[idx] { items[idx] = updated }
        } else {
            items.insert(item, at: 0)
        }
    }

    func update(_ item: MediaItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        guard items[idx] != item else { return }
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
        var candidate = items
        for index in candidate.indices where ids.contains(candidate[index].id) { candidate[index].isHidden = hidden }
        guard candidate != items else { return }
        items = candidate
        persist()
    }

    /// Add a tag (case-insensitive de-dupe) to an item.
    func addTag(_ tag: String, to item: MediaItem) {
        guard let clean = LibraryMutationPolicy.normalizedTag(tag), let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
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
        guard let clean = LibraryMutationPolicy.normalizedTag(tag) else { return }
        var candidate = items
        for index in candidate.indices where ids.contains(candidate[index].id)
            && !candidate[index].tags.contains(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) {
            candidate[index].tags.append(clean)
        }
        guard candidate != items else { return }
        items = candidate
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
        guard offset.isFinite, let idx = items.firstIndex(where: { $0.id == item.id }),
              items[idx].subtitleOffset != offset else { return }
        items[idx].subtitleOffset = offset
        persist()
    }

    /// Bulk favorite/unfavorite.
    func setFavorite(_ favorite: Bool, for ids: Set<UUID>) {
        var candidate = items
        for index in candidate.indices where ids.contains(candidate[index].id) { candidate[index].isFavorite = favorite }
        guard candidate != items else { return }
        items = candidate
        persist()
    }

    /// Bulk remove.
    func remove(ids: Set<UUID>) {
        items.removeAll { ids.contains($0.id) }
        persist()
    }

    func clearAll() {
        #if os(iOS)
        NovaPhoneWatchBridge.shared.invalidateEpoch(allowRecovery: true)
        #endif
        items.removeAll()
        persist()
    }

    /// Explicit Settings resets are local writes. Cloud deletion is represented
    /// separately by a tombstone, never by an ambiguous empty merge.
    func applySettingsDeletions() {
        let cloud = CloudSync.shared
        if cloud.consumeDeletion(.library, consumer: ".library") {
            cloudPushTask?.cancel()
            libraryNeedsRecovery = false
            collectionsNeedRecovery = false
            items = []
            collections = []
            queueIDs = []
            var saved = persistLocalOnly()
            do { try encoder.encode(collections).write(to: collectionsURL, options: .atomic) }
            catch { saved = false; lastPersistenceError = error.localizedDescription }
            if !saved { cloud.retryDeletion(.library, consumer: ".library") }
            defaults.set(try? encoder.encode(queueIDs), forKey: queueDefaultsKey)
            SpotlightIndexer.clear()
            writeWidgetSnapshot()
        }
        if cloud.consumeDeletion(.history, consumer: ".library") {
            cloudPushTask?.cancel()
            for index in items.indices {
                items[index].lastPlayedPosition = 0
                items[index].lastPlayedDate = nil
            }
            if !persistLocalOnly() { cloud.retryDeletion(.history, consumer: ".library") }
            writeWidgetSnapshot()
        }
    }

    func pushSettingsDataToCloud() {
        guard persistLocalOnly() else { return }
        CloudSync.shared.resumeSync(.library)
        CloudSync.shared.resumeSync(.history)
        pushToCloudNow()
        persistCollections()
        persistQueue()
    }

    func pullSettingsDataFromCloud() {
        CloudSync.shared.resumeSync(.library, pulling: true)
        CloudSync.shared.resumeSync(.history, pulling: true)
        // This is an explicit replacement request, including queue and collections.
        guard mergeFromCloudIfNewer(force: true) else { return }
        #if os(iOS)
        NovaPhoneWatchBridge.shared.invalidateEpoch()
        #endif
        if let data = CloudSync.shared.data(forKey: queueDefaultsKey),
           let decoded = try? decoder.decode([UUID].self, from: data) {
            queueIDs = LibraryMutationPolicy.unique(decoded)
            defaults.set(try? encoder.encode(queueIDs), forKey: queueDefaultsKey)
        }
        if let string = CloudSync.shared.string(forKey: collectionsCloudKey),
           let data = string.data(using: .utf8),
           let decoded = try? decoder.decode([MediaCollection].self, from: data) {
            let wasBlocked = collectionsNeedRecovery
            collectionsNeedRecovery = false
            if !persistCollections(decoded) { collectionsNeedRecovery = wasBlocked }
        }
    }

    func redactCloudWatchHistory() {
        guard let data = CloudSync.shared.rawMirrorData(forKey: cloudKey),
              var shared = try? decoder.decode([MediaItem].self, from: data) else { return }
        for index in shared.indices {
            shared[index].lastPlayedPosition = 0
            shared[index].lastPlayedDate = nil
        }
        if let redacted = try? encoder.encode(shared) {
            CloudSync.shared.replaceMirrorAfterDeletion(redacted, forKey: cloudKey)
        }
    }

    /// Resets only watch progress across the whole library.
    func clearWatchHistory() {
        #if os(iOS)
        NovaPhoneWatchBridge.shared.invalidateEpoch(allowRecovery: true)
        #endif
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

    private var queueDefaultsKey: String { PrefKey.libraryQueue }

    /// Loads the queue from local storage (called from init via loadQueue()).
    func loadQueue() {
        if let data = defaults.data(forKey: queueDefaultsKey),
           let ids = try? Coders.decoder.decode([UUID].self, from: data) {
            queueIDs = LibraryMutationPolicy.unique(ids)
            return // A deliberately empty local queue must not resurrect an old cloud copy.
        }
        if let data = CloudSync.shared.data(forKey: queueDefaultsKey),
           let ids = try? Coders.decoder.decode([UUID].self, from: data) {
            queueIDs = LibraryMutationPolicy.unique(ids)
        }
    }

    private func persistQueue() {
        if let data = try? Coders.encoder.encode(queueIDs) {
            defaults.set(data, forKey: queueDefaultsKey)
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
        guard queueIDs.contains(item.id) else { return }
        queueIDs.removeAll { $0 == item.id }
        persistQueue()
    }

    /// Reorders the queue (list-style move).
    func moveInQueue(from source: IndexSet, to destination: Int) {
        guard let candidate = LibraryMutationPolicy.moving(queueIDs, from: source, to: destination),
              candidate != queueIDs else { return }
        queueIDs = candidate
        persistQueue()
    }

    /// The queued items in order, skipping any that were removed from the library.
    var queuedItems: [MediaItem] {
        collapseToShow(LibraryMutationPolicy.orderedValues(keys: queueIDs, values: items, key: \.id))
    }

    /// The next thing to watch tonight: the first queued item, preferring one that is
    /// already in progress so an unfinished pick surfaces first.
    var upNextInQueue: MediaItem? {
        queuedItems.first(where: { $0.hasResumePoint }) ?? queuedItems.first
    }

    /// Items that have been watched or partially played, most recent first — powers a
    /// "Recently Watched" rail.
    var recentlyWatched: [MediaItem] {
        collapseToShow(
            items
                .filter { $0.lastPlayedDate != nil }
                .sorted { ($0.lastPlayedDate ?? .distantPast) > ($1.lastPlayedDate ?? .distantPast) }
        )
    }

}
// MARK: - Duplicate detection & merge

extension LibraryStore {

    /// A group of library items that appear to be the same title from different
    /// sources (matched by shared imdb/tmdb id, or by normalized title + year).
    struct DuplicateGroup: Identifiable {
        var id: UUID { items.map(\.id).min(by: { $0.uuidString < $1.uuidString }) ?? UUID() }
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
        LibraryMutationPolicy.duplicateKey(item)
    }

    /// Merges a duplicate group into a single item: keeps the most-complete record
    /// (most progress / has artwork), unions favorite status and the furthest watch
    /// progress, repoints any collections to the survivor, and removes the rest.
    func mergeDuplicates(_ group: DuplicateGroup) {
        let requested = Set(group.items.map(\.id))
        let current = items.filter { requested.contains($0.id) }
        guard current.count > 1, Set(current.map { duplicateKey(for: $0) }).count == 1 else { return }
        let group = DuplicateGroup(items: current)
        // Choose a survivor: prefer one with a contentID, then artwork, then most progress.
        let survivor = group.items.max { a, b in
            score(a) < score(b)
        } ?? group.items[0]

        guard let sIdx = items.firstIndex(where: { $0.id == survivor.id }) else { return }

        // Merge state from the others into the survivor.
        var merged = items[sIdx]
        for other in group.items where other.id != survivor.id {
            merged.isFavorite = merged.isFavorite || other.isFavorite
            merged.legalAccessConfirmed = merged.legalAccessConfirmed || other.legalAccessConfirmed
            merged.tags = LibraryMutationPolicy.unique(merged.tags + other.tags)
            let sources = merged.alternateSources + [LibraryMutationPolicy.location(other)] + other.alternateSources
            var seenSources: Set<String> = [LibraryMutationPolicy.location(merged).identity]
            merged.alternateSources = sources.filter { seenSources.insert($0.identity).inserted }
            if other.lastPlayedPosition > merged.lastPlayedPosition {
                merged.lastPlayedPosition = other.lastPlayedPosition
                merged.lastPlayedDate = other.lastPlayedDate ?? merged.lastPlayedDate
            }
            if merged.duration == nil { merged.duration = other.duration }
            if merged.posterURL == nil { merged.posterURL = other.posterURL }
            if merged.backdropURL == nil { merged.backdropURL = other.backdropURL }
            merged.addedDate = min(merged.addedDate, other.addedDate)
        }
        let removeIDs = Set(group.items.filter { $0.id != survivor.id }.map(\.id))
        let removedKeys = Dictionary(group.items.filter { $0.id != survivor.id }.map { ($0.contentKey, merged.contentKey) }, uniquingKeysWith: { first, _ in first })
        let remappedCollections = LibraryMutationPolicy.remapping(collections, keys: removedKeys)
        let remappedQueue = LibraryMutationPolicy.unique(queueIDs.map { removeIDs.contains($0) ? merged.id : $0 })
        var candidate = items
        candidate[sIdx] = merged
        candidate.removeAll { removeIDs.contains($0.id) }
        _ = commitLibraryChange(candidate, collections: remappedCollections, queue: remappedQueue)
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

}

// MARK: - Queries (used by Home/Library rows)

extension LibraryStore {

    /// The only media eligible for app-level hero placement. In-progress titles
    /// lead, followed by recently played/watched titles. Keeping this rule here
    /// prevents individual screens from quietly falling back to favorites,
    /// recently-added catalog items, recommendations, or bundled hero artwork.
    var viewingHistoryHeroItems: [MediaItem] {
        var seen = Set<String>()
        return (continueWatching + recentlyWatched)
            .filter { !$0.isHidden }
            .filter { seen.insert($0.contentKey).inserted }
            .prefix(10)
            .map { $0 }
    }

    var favorites: [MediaItem] {
        collapseToShow(items.filter { $0.isFavorite })
    }

    var continueWatching: [MediaItem] {
        // Collapse to one entry per show: the most recently played in-progress episode
        // represents the whole series, so a show isn't listed once per episode.
        collapseToShow(
            items
                .filter { $0.hasResumePoint }
                .sorted { ($0.lastPlayedDate ?? .distantPast) > ($1.lastPlayedDate ?? .distantPast) }
        )
    }

    var recentlyAdded: [MediaItem] {
        collapseToShow(items.sorted { $0.addedDate > $1.addedDate })
    }

    /// Collapses episodes so each series appears once (its most recent episode
    /// represents the whole show), while movies and non-episodic items stay
    /// individual. Used by Home rows so a show isn't listed once per episode.
    func collapseToShow(_ input: [MediaItem]) -> [MediaItem] {
        var showSlots: [String: Int] = [:]
        var result: [MediaItem] = []
        for item in input {
            if item.isSeries {
                let showKey = item.seriesTitle?.lowercased()
                    ?? item.contentID?.stableKey
                    ?? item.title.lowercased()
                if let slot = showSlots[showKey] {
                    if prefersAsSeriesRepresentative(item, over: result[slot]) {
                        result[slot] = item
                    }
                } else {
                    showSlots[showKey] = result.count
                    result.append(item)
                }
            } else {
                result.append(item)
            }
        }
        return result
    }

    /// A series is represented by the episode the user watched most recently. When
    /// neither episode has playback history, keep the newest added/highest numbered
    /// episode as a stable fallback. This rule is shared by every library-derived row.
    private func prefersAsSeriesRepresentative(_ candidate: MediaItem, over current: MediaItem) -> Bool {
        let candidatePlayed = candidate.lastPlayedDate ?? .distantPast
        let currentPlayed = current.lastPlayedDate ?? .distantPast
        if candidatePlayed != currentPlayed { return candidatePlayed > currentPlayed }
        if candidate.addedDate != current.addedDate { return candidate.addedDate > current.addedDate }
        let cSeason = candidate.episode?.season ?? 0
        let oSeason = current.episode?.season ?? 0
        if cSeason != oSeason { return cSeason > oSeason }
        return (candidate.episode?.number ?? 0) > (current.episode?.number ?? 0)
    }

    /// The library grid's entries: standalone movies as-is, but episodes collapsed so
    /// each series shows a single entry (represented by its most recently added
    /// episode) instead of one card per episode or per season. The individual episodes
    /// live under the show on its detail screen. Sorted by most recently added.
    var libraryEntries: [MediaItem] {
        let sorted = items.sorted {
            ($0.lastPlayedDate ?? $0.addedDate) > ($1.lastPlayedDate ?? $1.addedDate)
        }
        var seenShowKeys = Set<String>()
        var movieSlots: [String: Int] = [:]
        var result: [MediaItem] = []
        for item in sorted {
            if item.isSeries {
                // Group key: series identity — one entry for the whole show.
                let seriesKey = item.seriesTitle?.lowercased()
                    ?? item.contentID?.stableKey
                    ?? item.title.lowercased()
                if seenShowKeys.insert(seriesKey).inserted {
                    result.append(item)   // first (most recent) episode represents the show
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

    /// Most recently played episode for a series. All entry points use this single
    /// source so a show never resets to S1E1 after progress exists.
    func latestPlayedEpisode(imdb: String?, tmdb: Int?) -> EpisodeRef? {
        items.filter { item in
            guard item.episode != nil, item.lastPlayedDate != nil || item.lastPlayedPosition > 0 else { return false }
            return (imdb != nil && item.contentID?.imdb == imdb) || (tmdb != nil && item.contentID?.tmdb == tmdb)
        }
        .max { lhs, rhs in
            let ld = lhs.lastPlayedDate ?? .distantPast, rd = rhs.lastPlayedDate ?? .distantPast
            if ld != rd { return ld < rd }
            let le = lhs.episode!, re = rhs.episode!
            return le.season == re.season ? le.number < re.number : le.season < re.season
        }
        .flatMap { $0.episode.map { EpisodeRef(season: $0.season, number: $0.number) } }
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
