//
//  SimklClient.swift
//  Nova
//
//  SIMKL tracking provider. Uses SIMKL's PIN flow (TV/device friendly): show a
//  short code + verification URL (simkl.com/pin), the user approves on another
//  device, and Nova polls until an access token arrives. SIMKL access tokens never
//  expire, so there is no refresh step.
//
//  Only a client id is required (no secret) — set it in Settings ▸ SIMKL. Get one
//  at https://simkl.com/settings/developer/.
//
//  Endpoints per the SIMKL API (https://api.simkl.org). If SIMKL changes a shape,
//  the decoders below are the place to adjust.
//

import Foundation

// MARK: - Models

struct SimklPin: Codable {
    let userCode: String
    let verificationUrl: String
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case userCode = "user_code"
        case verificationUrl = "verification_url"
        case expiresIn = "expires_in"
        case interval
    }
}

private struct SimklPinStatus: Codable {
    let result: String
    let accessToken: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case result
        case accessToken = "access_token"
        case message
    }
}

private struct SimklSettings: Codable {
    struct User: Codable { let name: String? }
    let user: User?
}

/// One entry from /sync/all-items — either a movie or a show wrapper.
private struct SimklListEntry: Codable {
    let movie: SimklMedia?
    let show: SimklMedia?
    var media: SimklMedia? { movie ?? show }
    var isMovie: Bool { movie != nil }
}

private struct SimklAllItems: Codable {
    let movies: [SimklListEntry]?
    let shows: [SimklListEntry]?
}

private struct SimklMedia: Codable {
    let title: String?
    let year: Int?
    let ids: SimklIDs?
}

private struct SimklIDs: Codable {
    let simkl: Int?
    let imdb: String?
    let tmdb: IntOrString?
}

/// Trending JSON files sometimes encode tmdb as a string; accept either.
struct IntOrString: Codable {
    let intValue: Int?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { intValue = i }
        else if let s = try? c.decode(String.self) { intValue = Int(s) }
        else { intValue = nil }
    }
}

private struct SimklTrending: Codable {
    let title: String?
    let year: Int?
    let ids: SimklIDs?
}

// MARK: - Client

actor SimklClient {

    private static let base = URL(string: "https://api.simkl.com")!
    private static let trendingTVURL = URL(string: "https://data.simkl.in/discover/trending/tv/week_100.json")!

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let config = AppConfig.shared

    init(session: URLSession = AppNetworking.shared) {
        self.session = session
    }

    private var clientID: String? { config.simklClientID }
    private var token: String? { config.value(for: .simklAccessToken) }

    var isConfigured: Bool { clientID?.isEmpty == false }
    var isAuthenticated: Bool { token?.isEmpty == false }

    // MARK: - PIN OAuth

    /// Step 1: request a device/PIN code the user enters at simkl.com/pin.
    func requestPin() async throws -> SimklPin {
        guard let clientID else { throw TraktError.missingClientCredentials }
        var comps = URLComponents(url: Self.base.appendingPathComponent("oauth/pin"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "client_id", value: clientID)]
        let (data, http) = try await get(comps.url!, authed: false)
        guard (200...299).contains(http.statusCode) else { throw TraktError.http(http.statusCode) }
        return try decoder.decode(SimklPin.self, from: data)
    }

    /// Step 2: poll for the token. Returns the access token once the user approves,
    /// or nil while still pending.
    func pollForToken(userCode: String) async throws -> String? {
        guard let clientID else { throw TraktError.missingClientCredentials }
        var comps = URLComponents(url: Self.base.appendingPathComponent("oauth/pin/\(userCode)"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "client_id", value: clientID)]
        let (data, http) = try await get(comps.url!, authed: false)
        guard (200...299).contains(http.statusCode) else { return nil }
        let status = try? decoder.decode(SimklPinStatus.self, from: data)
        if status?.result == "OK", let token = status?.accessToken, !token.isEmpty {
            config.set(token, for: .simklAccessToken)
            return token
        }
        return nil   // pending
    }

    func signOut() {
        config.set(nil, for: .simklAccessToken)
    }

    /// SIMKL tokens never expire, so there is nothing to refresh — report whether a
    /// token exists so callers can gate on it uniformly with other providers.
    @discardableResult
    func refreshIfNeeded() async -> Bool { isAuthenticated }

    // MARK: - Connection

    func validateConnection() async -> ConnectionStatus {
        guard isConfigured else { return .notConfigured }
        guard isAuthenticated else { return .disconnected }
        do {
            let (data, http) = try await post(Self.base.appendingPathComponent("users/settings"),
                                              body: Data("{}".utf8), authed: true)
            if http.statusCode == 401 || http.statusCode == 403 { return .expired }
            guard (200...299).contains(http.statusCode) else {
                return .error("SIMKL request failed (HTTP \(http.statusCode)).")
            }
            let settings = try? decoder.decode(SimklSettings.self, from: data)
            return .connected(name: settings?.user?.name)
        } catch let TraktError.network(err) {
            return .error(err.localizedDescription)
        } catch {
            return .error("Couldn't reach SIMKL.")
        }
    }

    // MARK: - Reads

    func watchlist() async throws -> [CatalogItem] {
        guard isAuthenticated else { throw TraktError.notAuthenticated }
        async let movies = allItems(type: "movies", status: "plantowatch")
        async let shows  = allItems(type: "shows",  status: "plantowatch")
        return ((try? await movies) ?? []) + ((try? await shows) ?? [])
    }

    private func allItems(type: String, status: String) async throws -> [CatalogItem] {
        let url = Self.base.appendingPathComponent("sync/all-items/\(type)/\(status)")
        let (data, http) = try await get(url, authed: true)
        guard (200...299).contains(http.statusCode) else { throw TraktError.http(http.statusCode) }
        // SIMKL returns an empty body when there are no items.
        guard !data.isEmpty, let all = try? decoder.decode(SimklAllItems.self, from: data) else { return [] }
        let entries = (all.movies ?? []) + (all.shows ?? [])
        return entries.compactMap { catalogItem(from: $0.media, isMovie: $0.isMovie) }
    }

    func trendingShows() async throws -> [CatalogItem] {
        // Trending is served as static JSON (no auth). Attribution to SIMKL is
        // required wherever this is displayed.
        let (data, http) = try await get(Self.trendingTVURL, authed: false)
        guard (200...299).contains(http.statusCode) else { return [] }
        let items = (try? decoder.decode([SimklTrending].self, from: data)) ?? []
        return items.prefix(40).compactMap { t in
            catalogItem(title: t.title, year: t.year, ids: t.ids, isMovie: false)
        }
    }

    func syncNow() async { _ = try? await watchlist() }

    // MARK: - Writes (scrobble)

    /// SIMKL has no real-time scrobble. Map playback to its model: set a "watching"
    /// status on start, and write to history (mark watched) on stop past ~80%.
    @discardableResult
    func scrobble(action: ScrobbleAction,
                  contentID: ContentID,
                  episode: EpisodeRef?,
                  progress: Double) async -> Bool {
        guard isAuthenticated else { return false }
        switch action {
        case .start:
            return await addToList(status: "watching", contentID: contentID)
        case .stop where progress >= 80:
            return await addHistory(contentID: contentID, episode: episode)
        default:
            return false   // pause / early stop — nothing to send
        }
    }

    private func addToList(status: String, contentID: ContentID) async -> Bool {
        let key = contentID.type == .movie ? "movies" : "shows"
        var entry = idsPayload(for: contentID)
        entry["to"] = status
        let body: [String: Any] = [key: [entry]]
        return await postJSON(path: "sync/add-to-list", body: body)
    }

    private func addHistory(contentID: ContentID, episode: EpisodeRef?) async -> Bool {
        let body: [String: Any]
        if contentID.type == .movie {
            body = ["movies": [idsPayload(for: contentID)]]
        } else {
            var show = idsPayload(for: contentID)
            if let episode {
                show["seasons"] = [["number": episode.season,
                                    "episodes": [["number": episode.number]]]]
            }
            body = ["shows": [show]]
        }
        return await postJSON(path: "sync/history", body: body)
    }

    private func idsPayload(for c: ContentID) -> [String: Any] {
        var ids: [String: Any] = [:]
        if let imdb = c.imdb { ids["imdb"] = imdb }
        if let tmdb = c.tmdb { ids["tmdb"] = tmdb }
        return ["ids": ids]
    }

    // MARK: - Mapping

    private func catalogItem(from media: SimklMedia?, isMovie: Bool) -> CatalogItem? {
        catalogItem(title: media?.title, year: media?.year, ids: media?.ids, isMovie: isMovie)
    }

    private func catalogItem(title: String?, year: Int?, ids: SimklIDs?, isMovie: Bool) -> CatalogItem? {
        guard let title else { return nil }
        return CatalogItem(
            contentID: ContentID(imdb: ids?.imdb, tmdb: ids?.tmdb?.intValue, trakt: nil,
                                 type: isMovie ? .movie : .series),
            title: title,
            year: year
        )
    }

    // MARK: - Networking

    private func headers(authed: Bool) -> [String: String] {
        var h = ["Content-Type": "application/json"]
        if let clientID { h["simkl-api-key"] = clientID }
        if authed, let token { h["Authorization"] = "Bearer \(token)" }
        return h
    }

    private func get(_ url: URL, authed: Bool) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.timeoutInterval = 25
        for (k, v) in headers(authed: authed) { req.setValue(v, forHTTPHeaderField: k) }
        return try await run(req)
    }

    private func post(_ url: URL, body: Data, authed: Bool) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = body
        req.timeoutInterval = 25
        for (k, v) in headers(authed: authed) { req.setValue(v, forHTTPHeaderField: k) }
        return try await run(req)
    }

    private func postJSON(path: String, body: [String: Any]) async -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return false }
        let url = Self.base.appendingPathComponent(path)
        guard let (_, http) = try? await post(url, body: data, authed: true) else { return false }
        return (200...299).contains(http.statusCode)
    }

    private func run(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: req) }
        catch { throw TraktError.network(error) }
        guard let http = response as? HTTPURLResponse else { throw TraktError.http(-1) }
        return (data, http)
    }
}

// MARK: - TrackingProvider conformance

extension SimklClient: TrackingProvider {
    nonisolated var trackerID: TrackerID { .simkl }
    nonisolated var displayName: String { "SIMKL" }
    func configured() async -> Bool { isConfigured }
    func authenticated() async -> Bool { isAuthenticated }
}
