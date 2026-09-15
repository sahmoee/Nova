import Foundation
import Combine

// Isolated adapters for app-only services. The production LibraryStore, models,
// mutation policy and file policy are compiled unchanged by the runner.
enum PrefKey { static let cloudLibrary = "fixture.library", cloudLibraryRevision = "fixture.revision", cloudCollections = "fixture.collections", libraryQueue = "fixture.queue" }
enum SettingsDataDomain: Hashable { case library, history; var deletionKey: String { "fixture.delete.\(self)" } }
@MainActor final class CloudSync {
    static let shared = CloudSync()
    var values: [String: Any] = [:]
    var writes = 0
    var deletions = Set<SettingsDataDomain>()
    let externalChange = PassthroughSubject<[String], Never>()
    func data(forKey key: String) -> Data? { values[key] as? Data }
    func string(forKey key: String) -> String? { values[key] as? String }
    func double(forKey key: String) -> Double? { values[key] as? Double }
    func setData(_ data: Data, forKey key: String) { values[key] = data; writes += 1 }
    func setString(_ value: String, forKey key: String) { values[key] = value; writes += 1 }
    func setDouble(_ value: Double, forKey key: String) { values[key] = value; writes += 1 }
    func isPaused(_ domain: SettingsDataDomain) -> Bool { false }
    func deletionDate(_ domain: SettingsDataDomain) -> Double { 0 }
    func consumeDeletion(_ domain: SettingsDataDomain, consumer: String) -> Bool { deletions.remove(domain) != nil }
    func retryDeletion(_ domain: SettingsDataDomain, consumer: String) { deletions.insert(domain) }
    func resumeSync(_ domain: SettingsDataDomain, pulling: Bool = false) {}
    func rawMirrorData(forKey key: String) -> Data? { data(forKey: key) }
    func replaceMirrorAfterDeletion(_ data: Data, forKey key: String) { setData(data, forKey: key) }
    func flush() {}
}
enum Coders { static var encoder: JSONEncoder { JSONEncoder() }; static var decoder: JSONDecoder { JSONDecoder() } }
enum NovaLog { struct Log { func error(_ value: String) {} }; static let sync = Log() }
enum SpotlightIndexer { static func reindex(_ items: [MediaItem]) {}; static func clear() {} }
struct WidgetEntry { var id: String; var title: String; var subtitle: String; var posterURLString: String?; var progress: Double; var deepLink: String }
struct WidgetSnapshot { var continueWatching: [WidgetEntry]; var recentlyAdded: [WidgetEntry]; var updated: Date }
enum WidgetShared { static func write(_ value: WidgetSnapshot) {} }
enum WidgetRefresher { static func reload() {} }

@main @MainActor struct LibraryReliabilityChecks {
    static var count = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) { precondition(condition(), message); count += 1 }
    static func rejects(_ message: String, _ work: () throws -> Void) { do { try work(); fatalError(message) } catch { count += 1 } }
    static func item(_ title: String, server: UUID? = nil, native: String? = nil, tmdb: Int? = nil, addon: String? = nil) -> MediaItem {
        MediaItem(title: title, sourceType: server == nil ? .directURL : .jellyfin,
                  playbackURL: URL(string: "https://fixture.invalid/\(UUID().uuidString)")!,
                  metadata: MediaMetadata(mediaServerID: server, mediaServerItemID: native),
                  contentID: (tmdb != nil || addon != nil) ? ContentID(tmdb: tmdb, addonItemID: addon, type: .movie) : nil)
    }
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nova-library-fixture-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "nova-library-fixture-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = root.appendingPathComponent("nested/library.json")
        let sample = Data("fixture".utf8)
        try LibraryFilePolicy.write(sample, to: file, maximumBytes: 20)
        check(tryData(file) == sample, "Writes recreate parent folder")
        rejects("Oversized read must fail") { _ = try LibraryFilePolicy.read(file, maximumBytes: 2) }
        rejects("Oversized write must fail") { try LibraryFilePolicy.write(Data(repeating: 1, count: 21), to: file, maximumBytes: 20) }
        check(tryData(file) == sample, "Rejected write preserves original")
        let link = root.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        rejects("Do not follow library symlink") { _ = try LibraryFilePolicy.read(link, maximumBytes: 20) }
        rejects("Do not read directory as library") { _ = try LibraryFilePolicy.read(root, maximumBytes: 20) }

        check(LibraryMutationPolicy.unique([3,1,3,2,1]) == [3,1,2], "Ordered de-duplication")
        check(LibraryMutationPolicy.moving([1,2,3,4], from: IndexSet([0,2]), to: 4) == [2,4,1,3], "Noncontiguous reorder")
        check(LibraryMutationPolicy.moving([1,2], from: IndexSet([4]), to: 0) == nil, "Stale source cannot crash reorder")
        check(LibraryMutationPolicy.moving([1,2], from: IndexSet([0]), to: -1) == nil, "Negative move rejected")
        check(LibraryMutationPolicy.moving([1,2], from: IndexSet([0]), to: 3) == nil, "Oversized move rejected")
        check(LibraryMutationPolicy.normalizedTag("\n   \n") == nil, "Blank newline tag rejected")
        check(LibraryMutationPolicy.normalizedTag("\n Favorite \t") == "Favorite", "Tag whitespace normalized")
        let sid = UUID(), otherServer = UUID()
        var original = item("Film", server: sid, native: "42", addon: "jellyfin:42")
        original.isFavorite = true; original.isHidden = true; original.lastPlayedPosition = 127
        original.lastPlayedDate = Date(timeIntervalSince1970: 1_800_000_000)
        original.duration = 3_600; original.subtitleOffset = 1.25; original.tags = ["Private"]
        original.legalAccessConfirmed = true
        original.posterURL = URL(string: "https://fixture.invalid/poster")
        original.skipSegments = [SkipSegment(kind: .intro, start: 2, end: 20)]
        let alternate = item("Alternate", server: otherServer, native: "88", tmdb: 7)
        original.alternateSources = [LibraryMutationPolicy.location(alternate)]
        let fresh = item("Film", server: sid, native: "42", addon: "jellyfin:\(sid):42")
        let result = LibraryMutationPolicy.reconcile([fresh], existing: [original], connectionID: sid)
        let saved = result.items[0]
        check(result.items.count == 1 && saved.id == original.id, "Native source migration keeps record identity")
        check(saved.contentKey == fresh.contentKey, "Native source migration adopts scoped identity")
        check(saved.lastPlayedPosition == 127 && saved.lastPlayedDate == original.lastPlayedDate, "Resume and date survive refresh")
        check(saved.isFavorite && saved.isHidden && saved.tags == ["Private"], "Personal organization survives refresh")
        check(saved.legalAccessConfirmed && saved.subtitleOffset == 1.25, "Consent and subtitle offset survive refresh")
        check(saved.posterURL == original.posterURL && saved.skipSegments == original.skipSegments, "Sparse refresh retains enrichment")
        check(saved.duration == 3_600 && saved.addedDate == original.addedDate, "Runtime and added date survive refresh")
        check(saved.playbackURL == fresh.playbackURL, "Primary endpoint refreshes")
        check(result.renamedKeys[original.contentKey] == fresh.contentKey, "Changed keys captured for collection migration")
        let collection = MediaCollection(name: "Saved", contentKeys: [original.contentKey, fresh.contentKey])
        check(LibraryMutationPolicy.remapping([collection], keys: result.renamedKeys)[0].contentKeys == [fresh.contentKey], "Remapping deduplicates memberships")
        let missing = LibraryMutationPolicy.reconcile([], existing: [original], connectionID: sid)
        check(missing.items.count == 1 && missing.items[0].playbackURL == alternate.playbackURL, "Removing primary promotes other server")
        check(missing.items[0].metadata.mediaServerID == otherServer, "Fallback changes ownership")
        var noFallback = original; noFallback.alternateSources = []
        check(LibraryMutationPolicy.reconcile([], existing: [noFallback], connectionID: sid).items.isEmpty, "Last removed source leaves index")
        check(LibraryMutationPolicy.reconcile([], existing: [alternate], connectionID: sid).items == [alternate], "Other server untouched")
        var refreshedAlternate = alternate
        refreshedAlternate.playbackURL = URL(string: "https://fixture.invalid/new")!
        var freshWithAlternate = fresh; freshWithAlternate.alternateSources = [LibraryMutationPolicy.location(refreshedAlternate)]
        check(LibraryMutationPolicy.merged(freshWithAlternate, preserving: original).alternateSources.first?.playbackURL == refreshedAlternate.playbackURL, "Refreshed alternate wins over expired URL")
        let a = item("A", tmdb: 1), b = item("B", tmdb: 2)
        check(LibraryMutationPolicy.adding([a,b,a], to: []).map(\.id) == [b.id,a.id], "Bulk import preserves single-add order and deduplicates")
        check(LibraryMutationPolicy.orderedValues(keys: [b.id,a.id,b.id,UUID()], values: [a,b], key: \.id).map(\.id) == [b.id,a.id], "Ordered projection skips missing and repeated IDs")
        var show = a; show.contentID?.type = .series
        check(LibraryMutationPolicy.duplicateKey(a) != LibraryMutationPolicy.duplicateKey(show), "Movie and TV numeric IDs never collide")
        check(LibraryMutationPolicy.duplicateKey(item("")) != LibraryMutationPolicy.duplicateKey(item("")), "Blank titles are not duplicate evidence")

        CloudSync.shared.values = [:]
        let directory = root.appendingPathComponent("store")
        let store = LibraryStore(directory: directory, defaults: defaults)
        store.add(contentsOf: [a,b])
        let disk = directory.appendingPathComponent("library.json")
        check(store.items.count == 2 && store.lastPersistenceError == nil && tryData(disk) != nil, "Production store persists bulk import")
        var publications = 0
        let subscription = store.$items.dropFirst().sink { _ in publications += 1 }
        store.setFavorite(true, for: [a.id,b.id])
        check(publications == 1 && store.items.allSatisfy(\.isFavorite), "Bulk favorite publishes one array")
        store.setFavorite(true, for: [a.id,b.id])
        check(publications == 1, "Repeated bulk favorite avoids publication")
        store.setHidden(true, for: [a.id,b.id]); check(publications == 2, "Bulk hide publishes once")
        store.addTag(" \nWatch\n", to: [a.id,b.id]); check(publications == 3, "Bulk tagging publishes once")
        store.addTag("watch", to: [a.id,b.id]); check(publications == 3, "Tag case duplicate does not publish")
        store.setSubtitleOffset(.nan, for: a)
        check(store.item(id: a.id)?.subtitleOffset == 0 && store.lastPersistenceError == nil, "Nonfinite offset cannot poison whole-library encoding")
        subscription.cancel()
        let ownedCollection = store.createCollection(name: "Fixture")!
        store.addToCollection(ownedCollection.id, items: [a,b,a])
        check(store.collections[0].contentKeys.count == 2, "Collection batch has unique memberships")
        store.addToQueue(a); store.addToQueue(b)
        store.moveInQueue(from: IndexSet([99]), to: 0)
        check(store.queueIDs == [a.id,b.id], "Invalid production queue move leaves order intact")
        store.removeFromQueue(a); store.removeFromQueue(b)
        CloudSync.shared.setData(try Coders.encoder.encode([a.id]), forKey: PrefKey.libraryQueue)
        store.loadQueue()
        check(store.queueIDs.isEmpty, "Empty local queue is authoritative over old cloud queue")
        defaults.set(try Coders.encoder.encode([b.id,a.id,b.id]), forKey: PrefKey.libraryQueue)
        store.loadQueue(); check(store.queueIDs == [b.id,a.id], "Restored queue de-duplicates in order")

        CloudSync.shared.values = [:]
        let serverStore = LibraryStore(directory: root.appendingPathComponent("server-store"), defaults: UserDefaults(suiteName: suite + ".server")!)
        serverStore.add(original)
        let c = serverStore.createCollection(name: "Server")!
        serverStore.addToCollection(c.id, item: original)
        serverStore.addToQueue(original)
        check(serverStore.reconcileMediaServer([fresh], connectionID: sid), "Reconciliation reports durable success")
        check(serverStore.collections.first(where: { $0.id == c.id })?.contentKeys == [fresh.contentKey], "Production reconciliation migrates collection keys")
        check(serverStore.queueIDs == [original.id], "Reconciliation retains queue references")
        let before = serverStore.items
        check(!serverStore.reconcileMediaServer([alternate], connectionID: sid) && serverStore.items == before, "Wrong-server reconciliation rejected without deletion")
        check(serverStore.reconcileMediaServer([fresh], connectionID: sid) && serverStore.items == before, "Unchanged refresh succeeds without changing library")
        defaults.removePersistentDomain(forName: suite + ".server")

        // A duplicate sheet may remain open while the underlying titles change.
        CloudSync.shared.values = [:]
        let duplicateDefaults = UserDefaults(suiteName: suite + ".duplicates")!
        defer { duplicateDefaults.removePersistentDomain(forName: suite + ".duplicates") }
        let duplicateStore = LibraryStore(directory: root.appendingPathComponent("duplicates"), defaults: duplicateDefaults)
        var twin = item("A", tmdb: 3)
        twin.posterURL = URL(string: "https://fixture.invalid/art")
        duplicateStore.add(contentsOf: [a,twin])
        twin.contentID = a.contentID
        duplicateStore.update(twin)
        let group = duplicateStore.duplicateGroups()[0]
        check(group.id == duplicateStore.duplicateGroups()[0].id, "Duplicate group identity stays stable across queries")
        duplicateStore.toggleFavorite(a)
        duplicateStore.addTag("Preserve", to: a)
        duplicateStore.addToQueue(a)
        duplicateStore.mergeDuplicates(group)
        check(duplicateStore.items.count == 1 && duplicateStore.items[0].isFavorite, "Duplicate merge reads current favorite state")
        check(duplicateStore.items[0].tags.contains("Preserve"), "Duplicate merge preserves current tags")
        check(duplicateStore.items[0].alternateSources.contains(where: { $0.playbackURL == a.playbackURL }), "Duplicate merge preserves alternate playback source")
        check(duplicateStore.queueIDs == [duplicateStore.items[0].id], "Duplicate merge remaps queue to survivor")
        let staleGroup = group
        duplicateStore.mergeDuplicates(staleGroup)
        check(duplicateStore.items.count == 1, "Stale duplicate action does not resurrect removed record")

        CloudSync.shared.values = [:]
        let failingDir = root.appendingPathComponent("duplicate-failure")
        let failingDefaults = UserDefaults(suiteName: suite + ".failure")!
        defer { failingDefaults.removePersistentDomain(forName: suite + ".failure") }
        let failing = LibraryStore(directory: failingDir, defaults: failingDefaults)
        let plain = item("Same", addon: "first")
        var enriched = item("Same", addon: "second")
        enriched.posterURL = URL(string: "https://fixture.invalid/enriched")
        failing.add(contentsOf: [plain,enriched])
        let failureCollection = failing.createCollection(name: "Keep")!
        failing.addToCollection(failureCollection.id, item: plain)
        failing.addToQueue(plain)
        let failingGroup = failing.duplicateGroups()[0]
        let originalRows = failing.items, originalQueue = failing.queueIDs, originalCollections = failing.collections
        let failingCollectionsURL = failingDir.appendingPathComponent("collections.json")
        let originalCollectionData = try Data(contentsOf: failingCollectionsURL)
        try FileManager.default.removeItem(at: failingCollectionsURL)
        try FileManager.default.createDirectory(at: failingCollectionsURL, withIntermediateDirectories: false)
        failing.mergeDuplicates(failingGroup)
        check(failing.items == originalRows && failing.queueIDs == originalQueue, "Collection write failure prevents duplicate deletion and queue remap")
        check(failing.collections == originalCollections && failing.lastPersistenceError != nil, "Failed collection bridge preserves published memberships")
        try FileManager.default.removeItem(at: failingCollectionsURL)
        try originalCollectionData.write(to: failingCollectionsURL)
        let failingLibraryURL = failingDir.appendingPathComponent("library.json")
        try FileManager.default.removeItem(at: failingLibraryURL)
        try FileManager.default.createDirectory(at: failingLibraryURL, withIntermediateDirectories: false)
        failing.mergeDuplicates(failingGroup)
        check(failing.items == originalRows && failing.queueIDs == originalQueue, "Library failure rolls back duplicate records and queue bridge")
        check(failing.collections == originalCollections && tryData(failingCollectionsURL) == originalCollectionData, "Library failure restores original collection file")

        // Disk failure must not advertise the unsaved state to the cloud, including
        // a debounce that was scheduled by an earlier successful mutation.
        try await Task.sleep(for: .milliseconds(750))
        store.setFavorite(false, for: [a.id,b.id])
        try FileManager.default.removeItem(at: disk)
        try FileManager.default.createDirectory(at: disk, withIntermediateDirectories: false)
        let writesBeforeFailure = CloudSync.shared.writes
        store.add(item("Unsaved", tmdb: 77))
        check(store.lastPersistenceError != nil, "Save failure is visible")
        check(!store.items.contains(where: { $0.title == "Unsaved" }), "Failed save rolls memory back to durable library")
        try await Task.sleep(for: .milliseconds(750))
        check(CloudSync.shared.writes == writesBeforeFailure, "Failed write retires pending cloud publication")
        let durableIDs = store.items.map(\.id)
        let acceptedRevision = defaults.double(forKey: PrefKey.cloudLibraryRevision)
        let cloudEncoder = JSONEncoder(); cloudEncoder.dateEncodingStrategy = .iso8601
        CloudSync.shared.values[PrefKey.cloudLibrary] = try cloudEncoder.encode([fresh])
        CloudSync.shared.values[PrefKey.cloudLibraryRevision] = acceptedRevision + 10
        let queueBeforePull = store.queueIDs
        CloudSync.shared.values[PrefKey.libraryQueue] = try Coders.encoder.encode([fresh.id])
        store.pullSettingsDataFromCloud()
        check(store.queueIDs == queueBeforePull, "Failed library restore does not install another snapshot's queue")
        check(store.items.map(\.id) == durableIDs, "Failed cloud write leaves current library published")
        check(defaults.double(forKey: PrefKey.cloudLibraryRevision) == acceptedRevision, "Failed cloud write does not advance accepted revision")
        try FileManager.default.removeItem(at: disk)

        CloudSync.shared.values = [:]
        let corruptDir = root.appendingPathComponent("corrupt")
        try FileManager.default.createDirectory(at: corruptDir, withIntermediateDirectories: true)
        let corruptFile = corruptDir.appendingPathComponent("library.json")
        try sample.write(to: corruptFile)
        let corrupt = LibraryStore(directory: corruptDir, defaults: defaults)
        corrupt.add(a)
        check(tryData(corruptFile) == sample && corrupt.lastPersistenceError != nil, "Unreadable saved library is protected from ordinary writes")
        check(!corrupt.reconcileMediaServer([fresh], connectionID: sid), "Reindex cannot overwrite recovery data")
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        CloudSync.shared.values[PrefKey.cloudLibrary] = try enc.encode([b])
        CloudSync.shared.values[PrefKey.cloudLibraryRevision] = Date().timeIntervalSince1970 + 1
        corrupt.pullSettingsDataFromCloud()
        check(corrupt.items.map(\.id) == [b.id] && corrupt.lastPersistenceError == nil, "Explicit valid cloud restore recovers protected file")

        let badCollectionsDir = root.appendingPathComponent("bad-collections")
        try FileManager.default.createDirectory(at: badCollectionsDir, withIntermediateDirectories: true)
        let badCollectionsFile = badCollectionsDir.appendingPathComponent("collections.json")
        try sample.write(to: badCollectionsFile)
        CloudSync.shared.values = [:]
        let badCollections = LibraryStore(directory: badCollectionsDir, defaults: defaults)
        _ = badCollections.createCollection(name: "Should not replace recovery data")
        check(badCollections.collections.isEmpty && tryData(badCollectionsFile) == sample, "Corrupt collections do not publish or overwrite")
        check(badCollections.lastPersistenceError != nil, "Collection recovery failure is surfaced")
        print("PASS: \(count) library reliability checks")
    }
    static func tryData(_ file: URL) -> Data? { try? Data(contentsOf: file) }
}
