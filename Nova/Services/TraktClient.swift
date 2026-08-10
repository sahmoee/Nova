//
//  TraktClient.swift
//  Nova
//
//  Trakt client. Supports device-code OAuth (TV-friendly), reading the user's
//  watchlist and lists, and scrobbling playback progress (start/pause/stop) so
//  watched state and "up next" stay in sync with Trakt.
//
//  Client id/secret come from AppConfig (Settings or config file). Tokens are
//  stored in the Keychain and refreshed automatically when expired.
//

import Foundation

enum TraktError: LocalizedError {
    case missingClientCredentials
    case notAuthenticated
    case authorizationPending
    case network(Error)
    case http(Int)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .missingClientCredentials:
            return "No Trakt client id/secret set. Add them in Settings to connect Trakt."
        case .notAuthenticated:    return "Not signed in to Trakt."
        case .authorizationPending:return "Waiting for you to authorize on trakt.tv…"
        case .network(let e):      return "Network error contacting Trakt: \(e.localizedDescription)"
        case .http(let c):         return "Trakt request failed (HTTP \(c))."
        case .decoding:            return "Couldn't read the Trakt response."
        }
    }
}

/// The real, validated state of a service connection. Distinguishes "we have a
/// token string" from "the token actually works", so the UI never shows Connected
/// for an expired/revoked login. Used by Trakt (and mirrored by other services).
enum ConnectionStatus: Equatable {
    case notConfigured   // no client credentials set
    case disconnected    // configured but no token
    case connected(name: String?)
    case expired         // token present but rejected/unrefreshable
    case error(String)   // network or other failure while validating

    var isUsable: Bool { if case .connected = self { return true } else { return false } }
}

actor TraktClient {

    private static let base = URL(string: "https://api.trakt.tv")!
    private static let apiVersion = "2"

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private let config = AppConfig.shared
    private let keychain = KeychainStore.shared

    /// In-flight token refresh, shared by every caller. Trakt rotates the refresh
    /// token on each use (the old one is invalidated the moment a new pair is
    /// issued), so two requests that both 401 and both refresh would double-spend
    /// it: the first rotates successfully, the second posts the now-dead token,
    /// gets 401, and wrongly concludes the login is expired — exactly the "HTTP
    /// 401 / login expired" seen even though a valid token now exists. Coalescing
    /// concurrent refreshes onto one Task means the rotation happens once.
    private var refreshTask: Task<Bool, Never>?

    init(session: URLSession = AppNetworking.shared) {
        self.session = session
    }

    var isConfigured: Bool {
        (config.traktClientID?.isEmpty == false) && (config.traktClientSecret?.isEmpty == false)
    }

    var isAuthenticated: Bool {
        config.value(for: .traktAccessToken)?.isEmpty == false
    }

    // MARK: - Device OAuth

    /// Step 1: request a device code the user enters on trakt.tv/activate.
    func requestDeviceCode() async throws -> TraktDeviceCode {
        guard let clientID = config.traktClientID else { throw TraktError.missingClientCredentials }
        let url = Self.base.appendingPathComponent("oauth/device/code")
        let body = ["client_id": clientID]
        return try await postJSON(url, body: body, authed: false)
    }

    /// Step 2: poll for the token. Returns nil while the user hasn't authorized yet.
    func pollForToken(deviceCode: String) async throws -> TraktToken? {
        guard let clientID = config.traktClientID,
              let clientSecret = config.traktClientSecret else {
            throw TraktError.missingClientCredentials
        }
        let url = Self.base.appendingPathComponent("oauth/device/token")
        let body = [
            "code": deviceCode,
            "client_id": clientID,
            "client_secret": clientSecret
        ]

        let (data, http) = try await rawPost(url, jsonBody: body, headers: baseHeaders(authed: false))
        switch http.statusCode {
        case 200:
            let token = try decode(TraktToken.self, from: data)
            storeToken(token)
            return token
        case 400:
            // Pending — user hasn't authorized yet.
            return nil
        case 404, 409, 410, 418, 429:
            // expired/denied/slow-down/etc — surface as pending so caller can stop on timeout.
            return nil
        default:
            throw TraktError.http(http.statusCode)
        }
    }

    private func storeToken(_ token: TraktToken) {
        config.set(token.accessToken, for: .traktAccessToken)
        config.set(token.refreshToken, for: .traktRefreshToken)
    }

    func signOut() {
        config.set(nil, for: .traktAccessToken)
        config.set(nil, for: .traktRefreshToken)
    }

    /// Refreshes the access token using the stored refresh token. Single-flighted:
    /// concurrent callers share one network refresh so the rotating refresh token
    /// is spent exactly once. Returns whether a usable access token exists after.
    private func refreshTokenIfPossible() async -> Bool {
        if let refreshTask { return await refreshTask.value }
        let task = Task { await self.performTokenRefresh() }
        refreshTask = task
        let result = await task.value
        // Only clear if this call owns the current task (a later refresh may have
        // already replaced it), so the next 401 can start a fresh refresh.
        if refreshTask == task { refreshTask = nil }
        return result
    }

    private func performTokenRefresh() async -> Bool {
        guard let refresh = config.value(for: .traktRefreshToken),
              let clientID = config.traktClientID,
              let clientSecret = config.traktClientSecret else { return false }

        let url = Self.base.appendingPathComponent("oauth/token")
        let body = [
            "refresh_token": refresh,
            "client_id": clientID,
            "client_secret": clientSecret,
            "grant_type": "refresh_token"
        ]
        guard let (data, http) = try? await rawPost(url, jsonBody: body, headers: baseHeaders(authed: false)),
              http.statusCode == 200,
              let token = try? decoder.decode(TraktToken.self, from: data) else {
            return false
        }
        storeToken(token)
        return true
    }

    // MARK: - User data

    func currentUser() async throws -> TraktUser {
        let settings: TraktSettingsResponse = try await authedGet("users/settings")
        guard let user = settings.user else { throw TraktError.decoding(NSError(domain: "trakt", code: 0)) }
        return user
    }

    /// Publicly refresh the access token if a refresh token is available. Returns
    /// whether a usable access token exists afterward. Called after a backup restore
    /// so a restored (possibly-expired) token is renewed before first use.
    @discardableResult
    func refreshIfNeeded() async -> Bool {
        if config.value(for: .traktAccessToken)?.isEmpty == false { return true }
        return await refreshTokenIfPossible()
    }

    /// Live connection check: never trusts the mere presence of a token. If a token
    /// exists we hit users/settings; on 401 we refresh once and retry. The result
    /// tells the UI exactly what to show (Connected / Expired / Error).
    func validateConnection() async -> ConnectionStatus {
        guard isConfigured else { return .notConfigured }
        guard config.value(for: .traktAccessToken)?.isEmpty == false else { return .disconnected }
        do {
            let user = try await currentUser()
            return .connected(name: user.username)
        } catch TraktError.notAuthenticated, TraktError.http(401), TraktError.http(403) {
            // authedGet already tried a refresh-and-retry before surfacing these, so
            // reaching here means the stored token can't be renewed: it's expired.
            return .expired
        } catch let TraktError.network(err) {
            return .error(err.localizedDescription)
        } catch {
            return .error((error as? LocalizedError)?.errorDescription ?? "Couldn't reach Trakt.")
        }
    }

    /// The user's watchlist as catalog items.
    func watchlist() async throws -> [CatalogItem] {
        let items: [TraktListItem] = try await authedGet("users/me/watchlist", extended: true)
        return items.compactMap { catalogItem(from: $0) }
    }

    /// Performs an on-demand sync: refreshes the auth token if needed and pulls the
    /// user's watchlist so local state reflects Trakt. Best-effort; never throws to
    /// the caller so the UI can simply show a completion time.
    func syncNow() async {
        _ = await refreshTokenIfPossible()
        _ = try? await watchlist()
    }

    /// A user's custom list by slug.
    func list(slug: String) async throws -> [CatalogItem] {
        let items: [TraktListItem] = try await authedGet("users/me/lists/\(slug)/items", extended: true)
        return items.compactMap { catalogItem(from: $0) }
    }

    /// Trending shows (works without auth; useful for a discovery row).
    func trendingShows() async throws -> [CatalogItem] {
        let items: [TraktListItem] = try await get("shows/trending", authed: false, extended: true)
        return items.compactMap { catalogItem(from: $0) }
    }

    private func catalogItem(from item: TraktListItem) -> CatalogItem? {
        guard let media = item.media else { return nil }
        let ids = media.ids
        return CatalogItem(
            contentID: ContentID(imdb: ids?.imdb, tmdb: ids?.tmdb, trakt: ids?.trakt,
                                 type: item.contentType),
            title: media.title ?? "Untitled",
            year: media.year
        )
    }

    // MARK: - Scrobble

    /// Reports playback progress to Trakt. `action` is start, pause, or stop.
    /// `progress` is 0...100. Trakt auto-marks watched when stop fires past ~80%.
    @discardableResult
    func scrobble(action: ScrobbleAction,
                  contentID: ContentID,
                  episode: EpisodeRef?,
                  progress: Double) async -> Bool {
        guard isAuthenticated else { return false }

        var payload: [String: Any] = ["progress": min(max(progress, 0), 100)]

        if contentID.type == .movie {
            payload["movie"] = idsDict(for: contentID)
        } else {
            payload["show"] = idsDict(for: contentID)
            if let episode {
                payload["episode"] = ["season": episode.season, "number": episode.number]
            }
        }

        let url = Self.base.appendingPathComponent("scrobble/\(action.rawValue)")
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return false }

        // Try once; on 401 refresh and retry.
        if let ok = try? await sendScrobble(url: url, body: data), ok { return true }
        if await refreshTokenIfPossible(),
           let ok = try? await sendScrobble(url: url, body: data) {
            return ok
        }
        return false
    }

    private func sendScrobble(url: URL, body: Data) async throws -> Bool {
        let (_, http) = try await rawPost(url, rawBody: body, headers: baseHeaders(authed: true))
        return (200...299).contains(http.statusCode)
    }

    private func idsDict(for c: ContentID) -> [String: Any] {
        var ids: [String: Any] = [:]
        if let imdb = c.imdb { ids["imdb"] = imdb }
        if let tmdb = c.tmdb { ids["tmdb"] = tmdb }
        if let trakt = c.trakt { ids["trakt"] = trakt }
        return ["ids": ids]
    }

    // MARK: - Networking

    private func baseHeaders(authed: Bool) -> [String: String] {
        var h = [
            "Content-Type": "application/json",
            "trakt-api-version": Self.apiVersion
        ]
        if let clientID = config.traktClientID { h["trakt-api-key"] = clientID }
        if authed, let token = config.value(for: .traktAccessToken) {
            h["Authorization"] = "Bearer \(token)"
        }
        return h
    }

    private func authedGet<T: Decodable>(_ path: String, extended: Bool = false) async throws -> T {
        guard isAuthenticated else { throw TraktError.notAuthenticated }
        do {
            return try await get(path, authed: true, extended: extended)
        } catch TraktError.http(401) {
            if await refreshTokenIfPossible() {
                return try await get(path, authed: true, extended: extended)
            }
            throw TraktError.notAuthenticated
        }
    }

    private func get<T: Decodable>(_ path: String, authed: Bool, extended: Bool = false) async throws -> T {
        // Trakt only includes full IDs (notably the TMDB id we need for artwork) when
        // the request asks for extended=full. Append it when requested.
        var url = Self.base.appendingPathComponent(path)
        if extended {
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            comps?.queryItems = [URLQueryItem(name: "extended", value: "full")]
            if let u = comps?.url { url = u }
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 25
        for (k, v) in baseHeaders(authed: authed) { req.setValue(v, forHTTPHeaderField: k) }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw TraktError.network(error)
        }
        guard let http = response as? HTTPURLResponse else { throw TraktError.http(-1) }
        guard (200...299).contains(http.statusCode) else { throw TraktError.http(http.statusCode) }
        return try decode(T.self, from: data)
    }

    private func postJSON<T: Decodable>(_ url: URL, body: [String: String], authed: Bool) async throws -> T {
        let data = try JSONSerialization.data(withJSONObject: body)
        let (respData, http) = try await rawPost(url, rawBody: data, headers: baseHeaders(authed: authed))
        guard (200...299).contains(http.statusCode) else { throw TraktError.http(http.statusCode) }
        return try decode(T.self, from: respData)
    }

    private func rawPost(_ url: URL,
                         jsonBody: [String: String],
                         headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
        let data = try JSONSerialization.data(withJSONObject: jsonBody)
        return try await rawPost(url, rawBody: data, headers: headers)
    }

    private func rawPost(_ url: URL,
                         rawBody: Data,
                         headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = rawBody
        req.timeoutInterval = 25
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw TraktError.network(error)
        }
        guard let http = response as? HTTPURLResponse else { throw TraktError.http(-1) }
        return (data, http)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try decoder.decode(T.self, from: data) }
        catch { throw TraktError.decoding(error) }
    }
}

enum ScrobbleAction: String {
    case start
    case pause
    case stop
}
