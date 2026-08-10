//
//  TMDBAccountClient.swift
//  Nova
//
//  TMDB account as an optional tracker. TMDB has no "watched" concept, so this
//  provider contributes the user's TMDB watchlist (read) and can add titles to it
//  (write); playback scrobbling is a no-op. Auth uses TMDB v3 session flow:
//  request_token → user approves in browser → session_id (stored in Keychain).
//  Reuses the TMDB API key already configured for metadata.
//

import Foundation

struct TMDBRequestToken: Codable {
    let requestToken: String
    let expiresAt: String?
    enum CodingKeys: String, CodingKey {
        case requestToken = "request_token"
        case expiresAt = "expires_at"
    }
}

private struct TMDBSession: Codable {
    let sessionId: String?
    let success: Bool?
    enum CodingKeys: String, CodingKey { case sessionId = "session_id"; case success }
}

private struct TMDBAccount: Codable {
    let id: Int?
    let username: String?
    let name: String?
}

private struct TMDBWatchlistPage: Codable {
    let results: [TMDBWatchlistItem]?
    let page: Int?
    let totalPages: Int?
    enum CodingKeys: String, CodingKey { case results; case page; case totalPages = "total_pages" }
}

private struct TMDBWatchlistItem: Codable {
    let id: Int?
    let title: String?
    let name: String?
    let releaseDate: String?
    let firstAirDate: String?
    enum CodingKeys: String, CodingKey {
        case id, title, name
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
    }
}

actor TMDBAccountClient {

    private static let base = URL(string: "https://api.themoviedb.org/3")!
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let config = AppConfig.shared

    init(session: URLSession = AppNetworking.shared) {
        self.session = session
    }

    private var apiKey: String? { config.tmdbKey }
    private var sessionID: String? { config.value(for: .tmdbSessionID) }
    private var accountID: String? { config.value(for: .tmdbAccountID) }

    var isConfigured: Bool { apiKey?.isEmpty == false }
    var isAuthenticated: Bool { sessionID?.isEmpty == false }

    /// The URL the user visits to approve a request token.
    static func approvalURL(requestToken: String) -> URL? {
        URL(string: "https://www.themoviedb.org/authenticate/\(requestToken)")
    }

    // MARK: - Auth

    /// Step 1: create a request token the user approves in the browser.
    func createRequestToken() async throws -> TMDBRequestToken {
        guard apiKey != nil else { throw TraktError.missingClientCredentials }
        let (data, http) = try await get("authentication/token/new", query: [:])
        guard (200...299).contains(http.statusCode) else { throw TraktError.http(http.statusCode) }
        return try decoder.decode(TMDBRequestToken.self, from: data)
    }

    /// Step 2 (after approval): exchange the request token for a session, then store
    /// the session id and account id. Returns whether it succeeded.
    @discardableResult
    func createSession(requestToken: String) async throws -> Bool {
        guard apiKey != nil else { throw TraktError.missingClientCredentials }
        let body = try JSONSerialization.data(withJSONObject: ["request_token": requestToken])
        let (data, http) = try await post("authentication/session/new", body: body)
        guard (200...299).contains(http.statusCode),
              let sess = try? decoder.decode(TMDBSession.self, from: data),
              let id = sess.sessionId, !id.isEmpty else { return false }
        config.set(id, for: .tmdbSessionID)
        // Fetch and cache the numeric account id for subsequent list calls.
        if let (aData, aHTTP) = try? await get("account", query: ["session_id": id]),
           (200...299).contains(aHTTP.statusCode),
           let account = try? decoder.decode(TMDBAccount.self, from: aData),
           let accID = account.id {
            config.set(String(accID), for: .tmdbAccountID)
        }
        return true
    }

    func signOut() {
        config.set(nil, for: .tmdbSessionID)
        config.set(nil, for: .tmdbAccountID)
    }

    @discardableResult
    func refreshIfNeeded() async -> Bool { isAuthenticated }

    func validateConnection() async -> ConnectionStatus {
        guard isConfigured else { return .notConfigured }
        guard let sessionID else { return .disconnected }
        do {
            let (data, http) = try await get("account", query: ["session_id": sessionID])
            if http.statusCode == 401 || http.statusCode == 403 { return .expired }
            guard (200...299).contains(http.statusCode) else {
                return .error("TMDB request failed (HTTP \(http.statusCode)).")
            }
            let account = try? decoder.decode(TMDBAccount.self, from: data)
            return .connected(name: account?.username ?? account?.name)
        } catch let TraktError.network(err) {
            return .error(err.localizedDescription)
        } catch {
            return .error("Couldn't reach TMDB.")
        }
    }

    // MARK: - Reads

    func watchlist() async throws -> [CatalogItem] {
        guard let sessionID, let accountID else { throw TraktError.notAuthenticated }
        async let movies = watchlistPage(accountID: accountID, sessionID: sessionID,
                                         media: "movies", type: .movie)
        async let shows = watchlistPage(accountID: accountID, sessionID: sessionID,
                                        media: "tv", type: .series)
        return ((try? await movies) ?? []) + ((try? await shows) ?? [])
    }

    private func watchlistPage(accountID: String, sessionID: String,
                               media: String, type: ContentType) async throws -> [CatalogItem] {
        let (data, http) = try await get("account/\(accountID)/watchlist/\(media)",
                                         query: ["session_id": sessionID, "sort_by": "created_at.desc"])
        guard (200...299).contains(http.statusCode) else { throw TraktError.http(http.statusCode) }
        let page = try? decoder.decode(TMDBWatchlistPage.self, from: data)
        return (page?.results ?? []).compactMap { item in
            guard let id = item.id else { return nil }
            let title = item.title ?? item.name
            let dateStr = item.releaseDate ?? item.firstAirDate
            let year = dateStr.flatMap { Int($0.prefix(4)) }
            return CatalogItem(contentID: ContentID(imdb: nil, tmdb: id, trakt: nil, type: type),
                               title: title ?? "Untitled",
                               year: year)
        }
    }

    func trendingShows() async throws -> [CatalogItem] { [] }
    func syncNow() async { _ = try? await watchlist() }

    /// TMDB has no watched state; playback is not reported. (Watchlist writes happen
    /// elsewhere via addToWatchlist.)
    @discardableResult
    func scrobble(action: ScrobbleAction, contentID: ContentID,
                  episode: EpisodeRef?, progress: Double) async -> Bool { false }

    /// Add a title to the TMDB watchlist (used by the Watchlist action, not playback).
    @discardableResult
    func addToWatchlist(contentID: ContentID) async -> Bool {
        guard let sessionID, let accountID, let tmdb = contentID.tmdb else { return false }
        let body: [String: Any] = [
            "media_type": contentID.type == .movie ? "movie" : "tv",
            "media_id": tmdb,
            "watchlist": true
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let (_, http) = try? await post("account/\(accountID)/watchlist",
                                              body: data, query: ["session_id": sessionID])
        else { return false }
        return (200...299).contains(http.statusCode)
    }

    // MARK: - Networking

    private func url(_ path: String, query: [String: String]) -> URL {
        var comps = URLComponents(url: Self.base.appendingPathComponent(path),
                                  resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "api_key", value: apiKey ?? "")]
        items += query.map { URLQueryItem(name: $0.key, value: $0.value) }
        comps.queryItems = items
        return comps.url!
    }

    private func get(_ path: String, query: [String: String]) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url(path, query: query))
        req.timeoutInterval = 25
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await run(req)
    }

    private func post(_ path: String, body: Data,
                      query: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url(path, query: query))
        req.httpMethod = "POST"
        req.httpBody = body
        req.timeoutInterval = 25
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await run(req)
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

extension TMDBAccountClient: TrackingProvider {
    nonisolated var trackerID: TrackerID { .tmdb }
    nonisolated var displayName: String { "TMDB" }
    func configured() async -> Bool { isConfigured }
    func authenticated() async -> Bool { isAuthenticated }
}
