//
//  TrackingProvider.swift
//  Nova
//
//  A backend-agnostic abstraction over watch-tracking services (Trakt, SIMKL,
//  TMDB account, …). Each service is optional: the user may connect any number of
//  them. `TrackingHub` fans writes (scrobble/sync) out to every connected provider
//  and merges reads (watchlist/trending), so the rest of the app never depends on a
//  single service. Add a new tracker by conforming to `TrackingProvider` and adding
//  it to the hub in AppEnvironment.
//
//  `ConnectionStatus` and `ScrobbleAction` are defined in TraktClient.swift and
//  shared across all providers.
//

import Foundation
import UserNotifications
#if canImport(CloudKit)
import CloudKit
#endif

/// Stable identifier for each supported tracker.
enum TrackerID: String, CaseIterable, Codable, Sendable {
    case trakt
    case simkl
    case tmdb
    case nova
}

/// A watch-tracking backend. All members are async so actor-backed clients can
/// conform directly. Providers are optional and independent of one another.
protocol TrackingProvider: Sendable {
    nonisolated var trackerID: TrackerID { get }
    nonisolated var displayName: String { get }

    /// True when the service has the credentials it needs to attempt a connection.
    func configured() async -> Bool
    /// True when a usable access token is stored.
    func authenticated() async -> Bool
    /// A live, validated status (actually contacts the service).
    func validateConnection() async -> ConnectionStatus
    /// Clears stored tokens for this provider.
    func signOut() async
    /// Renews the access token if needed; returns whether one is usable afterward.
    @discardableResult func refreshIfNeeded() async -> Bool

    /// The user's watchlist / plan-to-watch as catalog items.
    func watchlist() async throws -> [CatalogItem]
    /// Trending shows for a discovery row (may be empty if unsupported).
    func trendingShows() async throws -> [CatalogItem]
    /// The user's watched/completed items (for import). Default: none.
    func watchedItems() async -> [CatalogItem]
    /// The user's rated items (item, 1...10) (for import). Default: none.
    func ratedItems() async -> [(CatalogItem, Int)]
    /// Best-effort pull to refresh local state; never throws.
    func syncNow() async

    /// Reports playback. Providers map this to their own model (Trakt scrobbles in
    /// real time; SIMKL sets a watching status on start and writes history on stop;
    /// TMDB has no watched state and ignores it). Returns whether anything was sent.
    @discardableResult
    func scrobble(action: ScrobbleAction,
                  contentID: ContentID,
                  episode: EpisodeRef?,
                  progress: Double) async -> Bool
}

extension TrackingProvider {
    // Sensible defaults so a provider can omit what it doesn't support.
    func trendingShows() async throws -> [CatalogItem] { [] }
    func syncNow() async { _ = await refreshIfNeeded() }
    func watchedItems() async -> [CatalogItem] { [] }
    func ratedItems() async -> [(CatalogItem, Int)] { [] }
}

/// Aggregates every configured tracker. Writes fan out to all connected providers;
/// reads merge and de-duplicate across them.
final class TrackingHub: Sendable {
    let providers: [any TrackingProvider]

    init(_ providers: [any TrackingProvider]) {
        self.providers = providers
    }

    /// Providers that currently have a usable token.
    func connectedProviders() async -> [any TrackingProvider] {
        var out: [any TrackingProvider] = []
        for p in providers where await p.authenticated() { out.append(p) }
        return out
    }

    /// True if at least one tracker is connected.
    func anyConnected() async -> Bool {
        for p in providers where await p.authenticated() { return true }
        return false
    }

    /// Merged watchlist across all connected trackers, de-duplicated by content key.
    func watchlist() async -> [CatalogItem] {
        var seen = Set<String>()
        var merged: [CatalogItem] = []
        for p in await connectedProviders() {
            guard let items = try? await p.watchlist() else { continue }
            for item in items where seen.insert(item.contentID.stableKey).inserted {
                merged.append(item)
            }
        }
        return merged
    }

    /// Merged trending shows across trackers that support it.
    func trendingShows() async -> [CatalogItem] {
        var seen = Set<String>()
        var merged: [CatalogItem] = []
        for p in providers {
            guard let items = try? await p.trendingShows(), !items.isEmpty else { continue }
            for item in items where seen.insert(item.contentID.stableKey).inserted {
                merged.append(item)
            }
        }
        return merged
    }

    /// Fan a scrobble out to every connected provider. Returns true if any accepted.
    @discardableResult
    func scrobble(action: ScrobbleAction,
                  contentID: ContentID,
                  episode: EpisodeRef?,
                  progress: Double) async -> Bool {
        var any = false
        for p in await connectedProviders() {
            if await p.scrobble(action: action, contentID: contentID,
                                episode: episode, progress: progress) { any = true }
        }
        return any
    }

    /// Refresh + pull on every connected provider.
    func syncNow() async {
        for p in await connectedProviders() { await p.syncNow() }
    }

    /// Refresh tokens on every provider that has one (e.g. after a backup restore).
    func refreshAll() async {
        for p in providers { _ = await p.refreshIfNeeded() }
    }

    /// Look up a provider instance by id (for per-service settings screens).
    func provider(_ id: TrackerID) -> (any TrackingProvider)? {
        providers.first { $0.trackerID == id }
    }
}

// MARK: - Trakt conformance (Trakt stays optional, now one provider among several)

extension TraktClient: TrackingProvider {
    nonisolated var trackerID: TrackerID { .trakt }
    nonisolated var displayName: String { "Trakt" }
    func configured() async -> Bool { isConfigured }
    func authenticated() async -> Bool { isAuthenticated }
    // validateConnection, signOut, refreshIfNeeded, watchlist, trendingShows,
    // syncNow, and scrobble already match the protocol.
}


// MARK: - Nova Tracker (first-party; combines the best of Trakt + SIMKL)
// Talks to the dedicated Nova Tracker backend (Cloudflare Worker + D1). It conforms to
// TrackingProvider so it runs in the hub beside Trakt/SIMKL during migration, and adds
// status + rating methods beyond the shared protocol. On-device caching / delta sync is a
// follow-up; v1 writes through and reads the watchlist.
//
// Set the deployed base URL via NovaConfig.json (novaTrackerBaseUrl) or AppConfig. Until a
// real URL is set, the provider reports not-configured so it stays dormant in the hub.

private struct NovaAccountResponse: Codable { let accountId: String; let token: String }
private struct NovaStatusListResponse: Codable { let items: [NovaStatusItem] }
private struct NovaStatusItem: Codable {
    let tmdb: Int?; let imdb: String?; let title: String?; let year: Int?; let media_type: String?
}

actor NovaTrackingProvider {
    static let placeholderBaseURL = "https://REPLACE-WITH-DEPLOYED-URL"

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let config = AppConfig.shared

    init(session: URLSession = AppNetworking.shared) { self.session = session }

    private var baseURLString: String { config.novaTrackerBaseURL ?? Self.placeholderBaseURL }
    private var base: URL? { URL(string: baseURLString) }
    private var token: String? { config.value(for: .novaTrackerToken) }

    var isConfigured: Bool { !baseURLString.isEmpty && baseURLString != Self.placeholderBaseURL }
    var isAuthenticated: Bool { token?.isEmpty == false }

    // MARK: - Account (zero-config: auto-register on first use)

    @discardableResult
    private func ensureAccount() async -> Bool {
        if isAuthenticated { return true }
        guard isConfigured else { return false }
        // Prefer a shared account keyed to the user's iCloud identity, so the same Apple ID
        // syncs tracking across all their devices (like Trakt/SIMKL). Fall back to an
        // anonymous device account if iCloud is unavailable.
        if await linkICloud() { return true }
        return await registerAnonymous()
    }

    private func linkICloud() async -> Bool {
        // NOTE: CKContainer.default() TRAPS (not a catchable error) unless the app's
        // entitlements include the CloudKit service. Nova has iCloud backup but not the
        // CloudKit capability, so this is gated behind a build flag. To enable true
        // cross-device identity: add the iCloud ▸ CloudKit capability in Signing &
        // Capabilities, then add NOVA_CLOUDKIT_IDENTITY to Active Compilation Conditions.
        #if NOVA_CLOUDKIT_IDENTITY && canImport(CloudKit)
        guard let base else { return false }
        let recordName = try? await CKContainer.default().userRecordID().recordName
        guard let external = recordName, !external.isEmpty else { return false }
        var req = URLRequest(url: base.appendingPathComponent("v1/account/link"))
        req.httpMethod = "POST"; req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["provider": "icloud", "externalId": external])
        guard let (data, resp) = try? await session.data(for: req),
              (resp as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) == true,
              let acct = try? decoder.decode(NovaAccountResponse.self, from: data) else { return false }
        config.set(acct.token, for: .novaTrackerToken)
        return true
        #else
        return false
        #endif
    }

    private func registerAnonymous() async -> Bool {
        guard let url = base?.appendingPathComponent("v1/account") else { return false }
        var req = URLRequest(url: url); req.httpMethod = "POST"; req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let (data, resp) = try? await session.data(for: req),
              (resp as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) == true,
              let acct = try? decoder.decode(NovaAccountResponse.self, from: data) else { return false }
        config.set(acct.token, for: .novaTrackerToken)
        return true
    }

    // MARK: - Offline cache + delta sync

    private var cacheKeyPrefix: String { "novaTracker.cache" }
    private func contentCacheKey(_ c: ContentID) -> String? {
        if let t = c.tmdb { return "tmdb:\(t)" }
        if let i = c.imdb { return "imdb:\(i)" }
        return nil
    }
    private func cachedStatuses() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: "\(cacheKeyPrefix).status") as? [String: String] ?? [:]
    }
    private func cachedRatings() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: "\(cacheKeyPrefix).rating") as? [String: Int] ?? [:]
    }
    private func writeCachedStatus(_ key: String?, _ status: String?) {
        guard let key else { return }
        var d = cachedStatuses(); if let status, status != "none" { d[key] = status } else { d[key] = nil }
        UserDefaults.standard.set(d, forKey: "\(cacheKeyPrefix).status")
    }
    private func writeCachedRating(_ key: String?, _ rating: Int?) {
        guard let key else { return }
        var d = cachedRatings(); if let rating, rating > 0 { d[key] = rating } else { d[key] = nil }
        UserDefaults.standard.set(d, forKey: "\(cacheKeyPrefix).rating")
    }

    /// Pull everything changed since the last sync into the local cache. Best-effort.
    func sync() async {
        guard await ensureAccount(), let base else { return }
        let since = UserDefaults.standard.double(forKey: "\(cacheKeyPrefix).lastSync")
        var comps = URLComponents(url: base.appendingPathComponent("v1/sync/pull"), resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "since", value: String(Int(since)))]
        guard let url = comps?.url else { return }
        var req = URLRequest(url: url); req.timeoutInterval = 25
        for (k, v) in authHeaders() { req.setValue(v, forHTTPHeaderField: k) }
        guard let (data, resp) = try? await session.data(for: req),
              (resp as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) == true,
              let pull = try? decoder.decode(NovaPullResponse.self, from: data) else { return }
        for row in pull.statuses ?? [] { writeCachedStatus(row.key, row.status) }
        for row in pull.ratings ?? [] { writeCachedRating(row.key, row.rating) }
        UserDefaults.standard.set(pull.now ?? Date().timeIntervalSince1970 * 1000, forKey: "\(cacheKeyPrefix).lastSync")
    }

    func signOut() { config.set(nil, for: .novaTrackerToken) }

    @discardableResult
    func refreshIfNeeded() async -> Bool { await ensureAccount() }

    func validateConnection() async -> ConnectionStatus {
        guard isConfigured else { return .notConfigured }
        guard await ensureAccount() else { return .error("Couldn't reach Nova Tracker.") }
        guard let (_, http) = try? await get("v1/settings") else { return .error("Couldn't reach Nova Tracker.") }
        if http.statusCode == 401 { return .expired }
        return (200...299).contains(http.statusCode) ? .connected(name: "Nova") : .error("HTTP \(http.statusCode)")
    }

    // MARK: - Reads

    func watchlist() async throws -> [CatalogItem] {
        guard await ensureAccount() else { throw TraktError.notAuthenticated }
        guard let (data, http) = try? await get("v1/status/plantowatch"),
              (200...299).contains(http.statusCode) else { return [] }
        let list = try? decoder.decode(NovaStatusListResponse.self, from: data)
        return (list?.items ?? []).compactMap { item in
            guard let title = item.title else { return nil }
            let type: ContentType = (item.media_type == "movie") ? .movie : .series
            return CatalogItem(contentID: ContentID(imdb: item.imdb, tmdb: item.tmdb, trakt: nil, type: type),
                               title: title, year: item.year)
        }
    }

    func trendingShows() async throws -> [CatalogItem] { [] }
    func syncNow() async { _ = await ensureAccount() }

    // MARK: - Writes: scrobble (Trakt-style real-time)

    @discardableResult
    func scrobble(action: ScrobbleAction, contentID: ContentID,
                  episode: EpisodeRef?, progress: Double) async -> Bool {
        guard await ensureAccount() else { return false }
        var body: [String: Any] = ["ids": ids(contentID), "type": mediaType(contentID), "progress": progress]
        if let episode { body["season"] = episode.season; body["number"] = episode.number }
        return await post("v1/scrobble/\(action.rawValue)", body: body)
    }

    // MARK: - Writes: status (SIMKL-style lists) + ratings

    /// status: plantowatch | watching | completed | hold | dropped
    @discardableResult
    func setStatus(_ status: String, for item: CatalogItem) async -> Bool {
        guard await ensureAccount() else { return false }
        writeCachedStatus(contentCacheKey(item.contentID), status)
        let body: [String: Any] = [
            "ids": ids(item.contentID), "type": mediaType(item.contentID),
            "status": status, "title": item.title, "year": item.year as Any
        ]
        return await post("v1/status", body: body)
    }

    /// rating 1...10 (0 clears). Optional season/number for per-episode ratings.
    @discardableResult
    func rate(_ rating: Int, contentID: ContentID, season: Int? = nil, number: Int? = nil) async -> Bool {
        guard await ensureAccount() else { return false }
        if season == nil, number == nil { writeCachedRating(contentCacheKey(contentID), rating) }
        var body: [String: Any] = ["ids": ids(contentID), "type": mediaType(contentID), "rating": rating]
        if let season { body["season"] = season }; if let number { body["number"] = number }
        return await post("v1/rating", body: body)
    }

    // MARK: - Helpers

    private func ids(_ c: ContentID) -> [String: Any] {
        var d: [String: Any] = [:]
        if let imdb = c.imdb { d["imdb"] = imdb }
        if let tmdb = c.tmdb { d["tmdb"] = tmdb }
        return d
    }
    private func mediaType(_ c: ContentID) -> String { c.type == .movie ? "movie" : "show" }

    private func authHeaders() -> [String: String] {
        var h = ["Content-Type": "application/json"]
        if let token { h["Authorization"] = "Bearer \(token)" }
        return h
    }

    private func get(_ path: String) async throws -> (Data, HTTPURLResponse) {
        guard let url = base?.appendingPathComponent(path) else { throw TraktError.http(-1) }
        var req = URLRequest(url: url); req.timeoutInterval = 20
        for (k, v) in authHeaders() { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw TraktError.http(-1) }
        return (data, http)
    }

    @discardableResult
    private func post(_ path: String, body: [String: Any]) async -> Bool {
        guard let url = base?.appendingPathComponent(path),
              let data = try? JSONSerialization.data(withJSONObject: body) else { return false }
        var req = URLRequest(url: url); req.httpMethod = "POST"; req.httpBody = data; req.timeoutInterval = 20
        for (k, v) in authHeaders() { req.setValue(v, forHTTPHeaderField: k) }
        guard let (_, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }
}

/// Aggregate tracking state for one title, for the detail screen.
struct NovaItemState: Sendable {
    var status: String?
    var rating: Int?
    var watched: Bool
    var position: Double?
    var duration: Double?
}
private struct NovaPullRow: Codable { let key: String?; let status: String?; let rating: Int? }
private struct NovaPullResponse: Codable {
    let now: Double?
    let statuses: [NovaPullRow]?
    let ratings: [NovaPullRow]?
}
private struct NovaItemResponse: Codable {
    let status: String?; let rating: Int?; let watched: Bool?; let position: Double?; let duration: Double?
}

extension NovaTrackingProvider {
    /// Current status + rating + playback + watched for a title.
    func itemState(_ contentID: ContentID) async -> NovaItemState? {
        guard await ensureAccount(), let base else { return nil }
        var comps = URLComponents(url: base.appendingPathComponent("v1/item"), resolvingAgainstBaseURL: false)
        var q: [URLQueryItem] = []
        if let imdb = contentID.imdb { q.append(.init(name: "imdb", value: imdb)) }
        if let tmdb = contentID.tmdb { q.append(.init(name: "tmdb", value: String(tmdb))) }
        guard !q.isEmpty else { return nil }
        comps?.queryItems = q
        guard let url = comps?.url else { return nil }
        var req = URLRequest(url: url); req.timeoutInterval = 20
        for (k, v) in authHeaders() { req.setValue(v, forHTTPHeaderField: k) }
        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let r = try? decoder.decode(NovaItemResponse.self, from: data) else {
            // Offline: answer from the local cache so the UI still shows status/rating.
            let key = contentCacheKey(contentID)
            return NovaItemState(status: key.flatMap { cachedStatuses()[$0] },
                                 rating: key.flatMap { cachedRatings()[$0] },
                                 watched: false, position: nil, duration: nil)
        }
        // Keep the cache in step with the server on every read.
        let key = contentCacheKey(contentID)
        writeCachedStatus(key, r.status); writeCachedRating(key, r.rating)
        return NovaItemState(status: r.status, rating: r.rating, watched: r.watched ?? false,
                             position: r.position, duration: r.duration)
    }
}

extension NovaTrackingProvider {
    /// One-time import from every connected provider: watchlist -> plan-to-watch,
    /// watched -> completed + history, ratings -> rating. Returns total items written.
    func importEverything(from providers: [any TrackingProvider]) async -> Int {
        guard await ensureAccount() else { return 0 }
        var count = 0
        for p in providers where p.trackerID != .nova {
            guard await p.authenticated() else { continue }
            if let list = try? await p.watchlist() {
                for item in list {
                    if await setStatus("plantowatch", for: item) { count += 1 }
                }
            }
            for item in await p.watchedItems() {
                let a = await setStatus("completed", for: item)
                let b = await scrobble(action: .stop, contentID: item.contentID, episode: nil, progress: 100)
                if a || b { count += 1 }
            }
            for (item, rating) in await p.ratedItems() {
                if await rate(rating, contentID: item.contentID) { count += 1 }
            }
        }
        return count
    }
}

extension NovaTrackingProvider: TrackingProvider {
    nonisolated var trackerID: TrackerID { .nova }
    nonisolated var displayName: String { "Nova" }
    func configured() async -> Bool { isConfigured }
    func authenticated() async -> Bool { isAuthenticated }
}


// MARK: - New-episode availability notifier
// For each tracked series, checks the most recently aired episode and — only if the
// user's own addons actually return a playable stream — posts a local notification
// ("New episode of X available to stream from Y"). Runs opportunistically when the app
// becomes active. (True background delivery would add a BGTask + Info.plist keys later.)
@MainActor
final class EpisodeAvailabilityNotifier {
    private let library: LibraryStore
    private let tmdb: TMDBClient
    private let catalog: CatalogService
    private var lastRun = Date.distantPast
    private let sentKey = "novaEpisodeNotify.sent"

    init(library: LibraryStore, tmdb: TMDBClient, catalog: CatalogService) {
        self.library = library; self.tmdb = tmdb; self.catalog = catalog
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Checks tracked series for newly-streamable episodes and notifies once each.
    func checkForNewStreamableEpisodes() async {
        guard Date().timeIntervalSince(lastRun) > 1800 else { return }   // at most every 30 min
        lastRun = Date()
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.notificationSettings())?.authorizationStatus == .authorized
        guard granted else { return }

        let ymd = DateFormatter(); ymd.dateFormat = "yyyy-MM-dd"; ymd.locale = Locale(identifier: "en_US_POSIX")
        let today = Calendar.current.startOfDay(for: Date())
        var sent = Set(UserDefaults.standard.stringArray(forKey: sentKey) ?? [])

        for m in trackedSeries() {
            guard let tmdbID = m.contentID?.tmdb else { continue }
            guard let last = try? await tmdb.lastEpisodeToAir(tmdbID: tmdbID),
                  let ds = last.air_date, let aired = ymd.date(from: ds), aired <= today,
                  let season = last.season_number, let number = last.episode_number else { continue }
            let key = "tmdb:\(tmdbID)|S\(season)E\(number)"
            if sent.contains(key) { continue }
            let cid = m.contentID ?? ContentID(imdb: nil, tmdb: tmdbID, trakt: nil, type: .series)
            let streams = await catalog.streams(for: cid, episode: EpisodeRef(season: season, number: number),
                                                preferredQuality: nil)
            guard let top = streams.first else { continue }   // only notify when actually streamable
            postNotification(show: m.displayTitle, season: season, episode: number,
                             source: top.addonName, count: streams.count)
            sent.insert(key)
            UserDefaults.standard.set(Array(sent), forKey: sentKey)
        }
    }

    private func postNotification(show: String, season: Int, episode: Int, source: String, count: Int) {
        let content = UNMutableNotificationContent()
        content.title = "New episode available"
        let code = String(format: "S%02dE%02d", season, episode)
        let src = count > 1 ? "\(source) and \(count - 1) more source\(count - 1 == 1 ? "" : "s")" : source
        content.body = "\(show) \(code) is ready to stream from \(src)."
        content.sound = .default
        let req = UNNotificationRequest(identifier: "novaEp-\(show)-\(code)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    private func trackedSeries() -> [MediaItem] {
        var seen = Set<Int>(); var out: [MediaItem] = []
        for m in (library.continueWatching + library.favorites + library.items) where m.isSeries {
            if let t = m.contentID?.tmdb, seen.insert(t).inserted { out.append(m) }
        }
        return out
    }
}
