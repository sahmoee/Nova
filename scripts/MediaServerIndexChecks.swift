import Foundation
import Combine

// Native-only stand-ins for app rendering models and Library/Keychain consumers.
// Tests execute the production client/store/policy; they do not claim to test Library persistence.
enum SourceType: Sendable { case jellyfin, plex, emby; var systemImage: String { "server.rack" } }
enum ContentType: Sendable { case movie, series }
struct ContentID: Sendable { var imdb: String?; var tmdb: Int?; var addonItemID: String?; var type: ContentType }
struct EpisodeRef: Sendable { var season: Int; var number: Int; var episodeTitle: String? }
struct MediaMetadata: Sendable {
    var filename: String? = nil; var fileSize: Int64? = nil; var resolution: String? = nil; var season: Int? = nil
    var episode: Int? = nil; var year: Int? = nil; var mediaServerID: UUID? = nil; var mediaServerItemID: String? = nil; var codec: String? = nil
}
struct MediaItem: Sendable {
    var title: String; var sourceType: SourceType; var playbackURL: URL; var posterURL: URL? = nil; var backdropURL: URL? = nil
    var duration: TimeInterval? = nil; var legalAccessConfirmed: Bool; var metadata: MediaMetadata
    var contentID: ContentID? = nil; var episode: EpisodeRef? = nil; var seriesTitle: String? = nil
}
@MainActor final class LibraryStore {
    var accepts = true
    var snapshots: [[MediaItem]] = []
    @discardableResult func reconcileMediaServer(_ items: [MediaItem], connectionID: UUID) -> Bool {
        guard accepts else { return false }; snapshots.append(items); return true
    }
}
enum NativeKeychainError: Error { case itemNotFound, failure }
struct KeychainStore {
    static let shared = Self()
    func getResult(_ account: String) -> Result<String, NativeKeychainError> { .failure(.itemNotFound) }
    func set(_ value: String, for account: String) throws { throw NativeKeychainError.failure }
    func delete(_ account: String) throws { throw NativeKeychainError.failure }
}
enum Coders { static var encoder: JSONEncoder { JSONEncoder() }; static var decoder: JSONDecoder { JSONDecoder() } }
enum AppNetworking { static let shared = URLSession(configuration: .ephemeral) }

actor FakeMediaClient: MediaServerIndexing {
    var indexCalls = 0, authCalls = 0
    var indexWaiters: [Int: CheckedContinuation<MediaServerIndexResult, Error>] = [:]
    var authWaiters: [Int: CheckedContinuation<(token: String, userID: String?), Error>] = [:]
    func index(connection: MediaServerConnection, token: String) async throws -> MediaServerIndexResult {
        indexCalls += 1; let id = indexCalls
        return try await withCheckedThrowingContinuation { indexWaiters[id] = $0 }
    }
    func authenticate(kind: MediaServerKind, baseURL: URL, username: String, password: String, token: String?) async throws -> (token: String, userID: String?) {
        authCalls += 1; let id = authCalls
        return try await withCheckedThrowingContinuation { authWaiters[id] = $0 }
    }
    func finishIndex(_ id: Int, result: MediaServerIndexResult) { indexWaiters.removeValue(forKey: id)?.resume(returning: result) }
    func finishAuth(_ id: Int) { authWaiters.removeValue(forKey: id)?.resume(returning: ("synthetic-only", "user")) }
    func counts() -> (Int, Int) { (indexCalls, authCalls) }
}
@MainActor final class MemoryCredentials {
    var values: [String: String] = [:]
    var reads = 0, writes = 0, removes = 0
    var failRemove = false, failRead = false
    var access: MediaServerCredentialAccess {
        .init(read: { [self] key in reads += 1; if failRead { throw NativeKeychainError.failure }; return values[key] },
              write: { [self] value, key in writes += 1; values[key] = value },
              remove: { [self] key in if failRemove { throw NativeKeychainError.failure }; removes += 1; values.removeValue(forKey: key) })
    }
}

@main enum MediaServerIndexChecks {
    @MainActor static func main() async throws {
        var checks = 0
        func check(_ condition: Bool, _ label: String) { precondition(condition, label); checks += 1 }
        func rejects(_ label: String, _ operation: () throws -> Void) { do { try operation(); preconditionFailure(label) } catch { checks += 1 } }
        let base = URL(string: "https://EXAMPLE.invalid/proxy/")!
        check(try MediaServerIndexPolicy.normalizedBase(base).absoluteString == "https://example.invalid/proxy", "Normalize base without losing reverse proxy")
        for address in ["ftp://example.invalid", "https://example.invalid?key=x", "https://u:p@example.invalid", "https://example.invalid/#fragment", "https://example.invalid/%2e%2e", "https://example.invalid:0"] {
            rejects("Reject unsafe base") { _ = try MediaServerIndexPolicy.normalizedBase(URL(string: address)!) }
        }
        let endpoint = try MediaServerIndexPolicy.endpoint(base: base, components: ["Users", "id ?+#", "Items"], query: ["token": "a&b+#?=c"])
        let endpointParts = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        check(endpointParts.path == "/proxy/Users/id ?+#/Items", "Path component delimiters remain path data")
        check(endpointParts.queryItems == [URLQueryItem(name: "token", value: "a&b+#?=c")], "Query secret round trips as one value")
        rejects("No path traversal IDs") { _ = try MediaServerIndexPolicy.endpoint(base: base, components: ["..", "Items"]) }
        rejects("No injected path slash") { _ = try MediaServerIndexPolicy.endpoint(base: base, components: ["a/b"]) }
        let resource = try MediaServerIndexPolicy.resource(base: base, path: "/library/parts/1/file.mkv?download=1&X-Plex-Token=old", token: "new&value")
        let parts = URLComponents(url: resource, resolvingAgainstBaseURL: false)!
        check(parts.path == "/proxy/library/parts/1/file.mkv", "Plex media retains reverse-proxy prefix")
        check(parts.queryItems?.filter { $0.name == "X-Plex-Token" } == [URLQueryItem(name: "X-Plex-Token", value: "new&value")], "Replace exactly one old provider token")
        for path in ["https://other.invalid/file", "//other.invalid/file", "/../file", "/%2e%2e/file", "/file#fragment", "file", "/a\\b"] {
            rejects("Only safe same-server relative resources") { _ = try MediaServerIndexPolicy.resource(base: base, path: path, token: "synthetic") }
        }
        check(MediaServerIndexPolicy.sameOrigin(base, URL(string: "https://example.invalid:443/other")!), "Default HTTPS port same origin")
        for destination in ["http://example.invalid/proxy", "https://else.invalid/proxy", "https://example.invalid:444/proxy", "https://u@example.invalid/proxy"] {
            check(!MediaServerIndexPolicy.sameOrigin(base, URL(string: destination)!), "Reject credential redirect destination")
        }
        check(MediaServerIndexPolicy.token(" \nabc\n") == "abc", "Trim token edges")
        check(MediaServerIndexPolicy.token("a\rb") == nil && MediaServerIndexPolicy.token(" ") == nil, "No empty or header-injecting token")
        check(MediaServerIndexPolicy.imdb("TT1234567") == "tt1234567", "Normalize valid IMDb")
        check(MediaServerIndexPolicy.imdb("not-a-title") == nil && MediaServerIndexPolicy.tmdb("-1") == nil, "Ignore invalid external IDs")
        check(MediaServerIndexPolicy.tmdb("123") == 123, "Positive TMDB")
        check(try MediaServerIndexPolicy.selectedLibraries(available: ["movies", "shows"], known: ["movies", "shows", "music"], selected: []) == ["movies", "shows"], "Default selection includes supported videos only")
        check(try MediaServerIndexPolicy.selectedLibraries(available: ["movies", "shows"], known: ["movies", "shows", "music"], selected: ["movies", "music"]) == ["movies"], "Legacy mixed video/music selection retains explicit videos")
        check(try MediaServerIndexPolicy.selectedLibraries(available: [], known: [], selected: []).isEmpty, "Explicit empty provider remains valid")
        rejects("Removed selected library isn't silently deselected") { _ = try MediaServerIndexPolicy.selectedLibraries(available: ["movies"], known: ["movies"], selected: ["removed"]) }
        rejects("Music-only selection cannot switch to every video") { _ = try MediaServerIndexPolicy.selectedLibraries(available: ["movies"], known: ["movies", "music"], selected: ["music"]) }
        rejects("Duplicate discovery IDs") { _ = try MediaServerIndexPolicy.selectedLibraries(available: ["movies"], known: ["movies", "movies"], selected: []) }
        rejects("Empty discovery identity") { _ = try MediaServerIndexPolicy.selectedLibraries(available: [], known: [""], selected: []) }
        rejects("Bound discovered libraries before iteration") { _ = try MediaServerIndexPolicy.selectedLibraries(available: [], known: (0...1024).map(String.init), selected: []) }
        let validRequestedFields: Set<String> = ["ProviderIds", "MediaSources", "MediaStreams", "Path"]
        check(Set(MediaServerIndexPolicy.jellyfinFields.split(separator: ",").map(String.init)) == validRequestedFields, "Jellyfin optional fields use actual ItemFields enum cases")
        var pager = MediaServerIndexPolicy.Pager(pageSize: 2)
        check(try pager.accept(ids: ["a", "b"], total: 3), "Known-total first page continues")
        check(try !pager.accept(ids: ["c"], total: 3), "Known-total final page")
        check(pager.offset == 3, "Offset tracks raw records")
        var unknown = MediaServerIndexPolicy.Pager(pageSize: 2)
        check(try unknown.accept(ids: ["a"], total: nil), "Unknown total short page still continues")
        check(try unknown.accept(ids: ["b"], total: nil), "Unknown totals do not stop at first size")
        check(try !unknown.accept(ids: [], total: nil), "Unknown total finishes only at empty page")
        var repeated = MediaServerIndexPolicy.Pager(pageSize: 2)
        _ = try repeated.accept(ids: ["a"], total: 2)
        rejects("Repeated page cannot be success") { _ = try repeated.accept(ids: ["a"], total: 2) }
        var short = MediaServerIndexPolicy.Pager(pageSize: 2)
        _ = try short.accept(ids: ["a"], total: 2)
        rejects("Early empty page is incomplete") { _ = try short.accept(ids: [], total: 2) }
        var changed = MediaServerIndexPolicy.Pager(pageSize: 2)
        _ = try changed.accept(ids: ["a"], total: 2)
        rejects("Changing total is retriable incomplete snapshot") { _ = try changed.accept(ids: ["b"], total: 3) }
        for total in [-1, 200_001] { var p = MediaServerIndexPolicy.Pager(); rejects("Invalid or huge total") { _ = try p.accept(ids: [], total: total) } }
        var wrongOffset = MediaServerIndexPolicy.Pager()
        rejects("Server ignoring requested offset") { _ = try wrongOffset.accept(ids: ["a"], total: 1, returnedOffset: 20) }
        var missingID = MediaServerIndexPolicy.Pager()
        rejects("Missing identity") { _ = try missingID.accept(ids: [""], total: 1) }
        var bigPage = MediaServerIndexPolicy.Pager(pageSize: 1)
        rejects("Oversized page") { _ = try bigPage.accept(ids: ["a", "b"], total: 2) }
        struct Row: Decodable { var id: String }
        let decoder = JSONDecoder()
        rejects("Jellyfin error object isn't empty library") { _ = try decoder.decode(JellyfinPage<Row>.self, from: Data("{}".utf8)) }
        let empty = try decoder.decode(JellyfinPage<Row>.self, from: Data(#"{"Items":[],"TotalRecordCount":0}"#.utf8))
        check(empty.items.isEmpty && empty.totalRecordCount == 0, "Explicit Jellyfin empty library")
        let unknownPage = try decoder.decode(JellyfinPage<Row>.self, from: Data(#"{"Items":[{"id":"a"}]}"#.utf8))
        check(unknownPage.totalRecordCount == nil, "Absent total remains unknown")
        rejects("Plex malformed container isn't empty") { _ = try decoder.decode(PlexMetadataContainer.self, from: Data("{}".utf8)) }
        let plexEmpty = try decoder.decode(PlexMetadataContainer.self, from: Data(#"{"size":0,"totalSize":0}"#.utf8))
        check(plexEmpty.metadata.isEmpty, "Plex explicit empty without Metadata accepted")
        rejects("Plex count mismatch") { _ = try decoder.decode(PlexMetadataContainer.self, from: Data(#"{"size":2,"Metadata":[]}"#.utf8)) }
        let emptySections = try decoder.decode(PlexSectionContainer.self, from: Data(#"{"size":0}"#.utf8))
        check(emptySections.directory.isEmpty, "Plex empty section list")
        rejects("Plex malformed sections") { _ = try decoder.decode(PlexSectionContainer.self, from: Data("{}".utf8)) }
        var gate = MediaServerOperationGate(); let id = UUID(), old = gate.begin(id), new = gate.begin(id)
        check(!gate.owns(old, id: id) && gate.owns(new, id: id), "New generation supersedes old")
        gate.finish(old, id: id); check(gate.owns(new, id: id), "Old cleanup cannot retire new work")
        gate.retire(id); check(!gate.owns(new, id: id), "Removal retires work")
        var connection = MediaServerConnection(kind: .plex, name: "Synthetic", baseURL: base)
        let legacy = Data("{\"id\":\"\(connection.id)\",\"kind\":\"plex\",\"name\":\"Legacy\",\"baseURL\":\"https://example.invalid\"}".utf8)
        let decoded = try decoder.decode(MediaServerConnection.self, from: legacy)
        check(decoded.autoRefresh && decoded.indexedItemCount == 0 && decoded.selectedLibraryIDs.isEmpty, "Legacy optional configuration defaults")
        var other = connection; other.baseURL = URL(string: "https://else.invalid")!
        check(!other.mayReuseCredential(from: connection), "Changed endpoint can't reuse saved token")
        other = connection; other.username = "Other"
        check(!other.mayReuseCredential(from: connection), "Changed user can't reuse saved token")
        other = connection; other.kind = .jellyfin
        check(!other.mayReuseCredential(from: connection), "Changed provider can't reuse saved token")
        other = connection; other.baseURL = URL(string: "https://example.invalid/proxy")!
        check(other.mayReuseCredential(from: connection), "Equivalent normalized endpoint may reuse token")

        let suite = "nova-media-index-checks-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        // Only this unique suite is used; never the app defaults or Keychain.
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = LibraryStore(), fake = FakeMediaClient(), vault = MemoryCredentials()
        let store = MediaServerStore(library: library, client: fake, defaults: defaults, credentials: vault.access)
        connection.selectedLibraryIDs = ["movies", "music"]
        try store.save(connection, secret: "synthetic-only")
        check(store.connections.count == 1 && vault.writes == 1, "Configured secret persists through injected credential owner")
        func waitFor(_ index: Int, auth: Int = 0) async {
            for _ in 0..<100_000 {
                let counts = await fake.counts(); if counts.0 >= index && counts.1 >= auth { return }; await Task.yield()
            }
            preconditionFailure("Synthetic client never reached requested operation")
        }
        let result = MediaServerIndexResult(libraries: [MediaServerLibrary(id: "movies", name: "Movies", kind: "movie")], items: [])
        let first = Task { try await store.sync(connection.id) }
        await waitFor(1)
        let joined = Task { try await store.sync(connection.id) }
        await Task.yield()
        let counts = await fake.counts(); check(counts.0 == 1, "Concurrent refresh coalesces")
        await fake.finishIndex(1, result: result)
        try await first.value; try await joined.value
        check(library.snapshots.count == 1 && store.syncingIDs.isEmpty, "Coalesced result reconciles exactly once")
        check(store.connections[0].lastIndexed != nil, "Successful reconciliation marks timestamp")
        check(store.connections[0].selectedLibraryIDs == ["movies"], "Successful snapshot persists migrated video selection")
        let stale = Task { try await store.sync(connection.id) }; await waitFor(2)
        connection.name = "Changed"; try store.save(connection, secret: "synthetic-new")
        let current = Task { try await store.sync(connection.id) }; await waitFor(3)
        await fake.finishIndex(2, result: result)
        do { try await stale.value; preconditionFailure("Stale refresh accepted") } catch { checks += 1 }
        check(library.snapshots.count == 1 && store.syncingIDs.contains(connection.id), "Old completion cannot reconcile or clear new progress")
        await fake.finishIndex(3, result: result); try await current.value
        check(library.snapshots.count == 2 && store.connections[0].name == "Changed", "New generation commits")
        library.accepts = false
        let before = store.connections[0].lastIndexed
        let failedSave = Task { try await store.sync(connection.id) }; await waitFor(4)
        await fake.finishIndex(4, result: result)
        do { try await failedSave.value; preconditionFailure("Rejected library commit became success") } catch { checks += 1 }
        check(store.connections[0].lastIndexed == before && store.connections[0].lastError != nil, "Failed local commit preserves timestamp and reports error")
        store.remove(connection, removeIndexedItems: true)
        check(store.connections.count == 1 && vault.removes == 0, "Failed library removal retains credentials and configuration")
        library.accepts = true
        vault.failRead = true
        do { try await store.sync(connection.id); preconditionFailure("Credential failure ignored") } catch { checks += 1 }
        check(store.connections[0].lastError != nil && store.syncingIDs.isEmpty, "Credential failures clear progress and surface error")
        vault.failRead = false
        let removed = Task { try await store.sync(connection.id) }; await waitFor(5)
        store.remove(connection, removeIndexedItems: false)
        await fake.finishIndex(5, result: result)
        do { try await removed.value; preconditionFailure("Removed server reconciled") } catch { checks += 1 }
        check(store.connections.isEmpty && library.snapshots.count == 2, "Removed server is not resurrected by late result")
        try store.save(connection, secret: "synthetic")
        let authenticating = Task { try await store.connect(connection, password: "", token: "explicit-synthetic") }
        await waitFor(5, auth: 1)
        store.remove(connection, removeIndexedItems: false)
        await fake.finishAuth(1)
        do { _ = try await authenticating.value; preconditionFailure("Late authentication saved removed server") } catch { checks += 1 }
        check(store.connections.isEmpty && vault.values[connection.tokenAccount] == nil, "Removal wins over in-flight authentication")
        let corrupt = Data("preserve settings".utf8); defaults.set(corrupt, forKey: "media.servers.v1")
        let damaged = MediaServerStore(library: library, client: fake, defaults: defaults, credentials: vault.access)
        rejects("Corrupt settings block writes") { try damaged.save(connection, secret: "synthetic") }
        damaged.remove(connection, removeIndexedItems: false)
        check(defaults.data(forKey: "media.servers.v1") == corrupt && damaged.statusMessage != nil, "Corrupt original remains preserved with visible error")
        print("Media-server native checks passed: \(checks)")
    }
}
