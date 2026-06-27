//
//  RealDebridClient.swift
//  FrameTV
//
//  Networking actor for the Real-Debrid REST API (v1.0).
//  The token is injected per-call from the Keychain; it is never logged.
//
//  NOTE: This is wired for real calls. In Phase 1/2 the UI can run without a
//  token; screens that need it will prompt the user. Phase 3 activates it.
//

import Foundation

// MARK: - Errors

enum RealDebridError: LocalizedError {
    case missingToken
    case invalidResponse
    case unauthorized          // 401 — bad/expired token
    case forbidden             // 403 — e.g. account not premium for an action
    case notReady              // torrent not finished
    case http(Int)
    case network(Error)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .missingToken:    return "No Real-Debrid token set. Add yours in Settings."
        case .invalidResponse: return "Real-Debrid returned an unexpected response."
        case .unauthorized:    return "Your Real-Debrid token is invalid or expired."
        case .forbidden:       return "This action isn't available on your Real-Debrid account."
        case .notReady:        return "This torrent isn't ready yet. Try again shortly."
        case .http(let code):  return "Real-Debrid request failed (HTTP \(code))."
        case .network(let e):  return "Network error contacting Real-Debrid: \(e.localizedDescription)"
        case .decoding:        return "Couldn't read the Real-Debrid response."
        }
    }
}

// MARK: - Endpoint

enum RealDebridEndpoint {
    case user
    case unrestrictLink
    case downloads
    case torrents
    case torrentInfo(String)
    case addMagnet
    case selectFiles(String)
    case streamingTranscode(String)
    case mediaInfo(String)

    var path: String {
        switch self {
        case .user:                      return "/user"
        case .unrestrictLink:            return "/unrestrict/link"
        case .downloads:                 return "/downloads"
        case .torrents:                  return "/torrents"
        case .torrentInfo(let id):       return "/torrents/info/\(id)"
        case .addMagnet:                 return "/torrents/addMagnet"
        case .selectFiles(let id):       return "/torrents/selectFiles/\(id)"
        case .streamingTranscode(let id):return "/streaming/transcode/\(id)"
        case .mediaInfo(let id):         return "/streaming/mediaInfos/\(id)"
        }
    }

    var method: String {
        switch self {
        case .user, .downloads, .torrents, .torrentInfo,
             .streamingTranscode, .mediaInfo:
            return "GET"
        case .unrestrictLink, .addMagnet, .selectFiles:
            return "POST"
        }
    }
}

// MARK: - Client

final actor RealDebridClient {

    static let baseURL = URL(string: "https://api.real-debrid.com/rest/1.0")!

    private let session: URLSession
    private let decoder: JSONDecoder

    /// Token provider closure so we always read the freshest value from Keychain.
    private let tokenProvider: @Sendable () -> String?

    init(
        session: URLSession = .shared,
        tokenProvider: @escaping @Sendable () -> String? = { KeychainStore.shared.realDebridToken }
    ) {
        let config = session.configuration
        config.timeoutIntervalForRequest = 30
        self.session = session
        self.tokenProvider = tokenProvider
        self.decoder = JSONDecoder()
    }

    // MARK: - Public API

    func validateToken() async throws -> RealDebridUser {
        try await request(.user)
    }

    func unrestrictLink(_ link: String) async throws -> UnrestrictedLink {
        try await request(.unrestrictLink, form: ["link": link])
    }

    func addMagnet(_ magnet: String) async throws -> TorrentAddResponse {
        try await request(.addMagnet, form: ["magnet": magnet])
    }

    func torrentInfo(id: String) async throws -> TorrentInfo {
        try await request(.torrentInfo(id))
    }

    func selectFiles(torrentID: String, fileIDs: [String]) async throws {
        let value = fileIDs.isEmpty ? "all" : fileIDs.joined(separator: ",")
        try await requestNoContent(.selectFiles(torrentID), form: ["files": value])
    }

    func downloads() async throws -> [DebridDownload] {
        try await request(.downloads)
    }

    func streamingTranscode(id: String) async throws -> StreamingLinks {
        try await request(.streamingTranscode(id))
    }

    func mediaInfo(id: String) async throws -> MediaInfo {
        try await request(.mediaInfo(id))
    }

    // MARK: - Request plumbing

    private func makeRequest(_ endpoint: RealDebridEndpoint,
                             form: [String: String]?) throws -> URLRequest {
        guard let token = tokenProvider(), !token.isEmpty else {
            throw RealDebridError.missingToken
        }

        let url = Self.baseURL.appendingPathComponent(String(endpoint.path.dropFirst()))
        var req = URLRequest(url: url)
        req.httpMethod = endpoint.method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        if let form, endpoint.method == "POST" {
            req.setValue("application/x-www-form-urlencoded",
                         forHTTPHeaderField: "Content-Type")
            req.httpBody = Self.encodeForm(form).data(using: .utf8)
        }
        return req
    }

    private func request<T: Decodable>(_ endpoint: RealDebridEndpoint,
                                       form: [String: String]? = nil) async throws -> T {
        let data = try await perform(endpoint, form: form)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw RealDebridError.decoding(error)
        }
    }

    private func requestNoContent(_ endpoint: RealDebridEndpoint,
                                  form: [String: String]? = nil) async throws {
        _ = try await perform(endpoint, form: form)
    }

    private func perform(_ endpoint: RealDebridEndpoint,
                         form: [String: String]?) async throws -> Data {
        let req = try makeRequest(endpoint, form: form)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw RealDebridError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw RealDebridError.invalidResponse
        }

        switch http.statusCode {
        case 200...299:
            return data
        case 401:
            throw RealDebridError.unauthorized
        case 403:
            throw RealDebridError.forbidden
        case 503:
            // Real-Debrid uses 503 for "torrent not ready / processing" in some flows.
            throw RealDebridError.notReady
        default:
            throw RealDebridError.http(http.statusCode)
        }
    }

    // MARK: - Helpers

    private static func encodeForm(_ params: [String: String]) -> String {
        params.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: .rdFormAllowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: .rdFormAllowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }
}

private extension CharacterSet {
    /// Allowed characters for x-www-form-urlencoded values (RFC 3986 unreserved).
    static let rdFormAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}
