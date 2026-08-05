//
//  RealDebridClient.swift
//  Nova
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
    case instantAvailability([String])

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
        case .instantAvailability(let hashes):
            return "/torrents/instantAvailability/" + hashes.joined(separator: "/")
        }
    }

    var method: String {
        switch self {
        case .user, .downloads, .torrents, .torrentInfo,
             .streamingTranscode, .mediaInfo, .instantAvailability:
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
        session: URLSession = AppNetworking.shared,
        tokenProvider: @escaping @Sendable () -> String? = { KeychainStore.shared.realDebridToken }
    ) {
        // FIX: mutating `session.configuration` here was a no-op — URLSession returns
        // a COPY of its configuration, so the intended 30s timeout never applied.
        // The timeout is now set per-request in makeRequest instead.
        self.session = session
        self.tokenProvider = tokenProvider
        self.decoder = JSONDecoder()
    }

    // MARK: - Public API

    /// Batch instant-availability check: one request for up to ~40 hashes instead
    /// of a call per stream. Returns the (lowercased) hashes that are cached.
    func instantAvailability(hashes: [String]) async throws -> Set<String> {
        guard !hashes.isEmpty else { return [] }
        let batch = Array(hashes.prefix(40)).map { $0.lowercased() }
        let req = try makeRequest(.instantAvailability(batch), form: nil)
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw RealDebridError.invalidResponse
        }
        // Response shape: { "<hash>": { "rd": [ {...variants} ] } } — a hash is
        // cached when any variant list is non-empty. Parsed leniently with
        // JSONSerialization because variant payloads differ between hosts.
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        var available: Set<String> = []
        for (hash, value) in root {
            guard let dict = value as? [String: Any] else { continue }
            for (_, hosterValue) in dict {
                if let variants = hosterValue as? [Any], !variants.isEmpty {
                    available.insert(hash.lowercased())
                    break
                }
                if let variants = hosterValue as? [String: Any], !variants.isEmpty {
                    available.insert(hash.lowercased())
                    break
                }
            }
        }
        return available
    }

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

    // MARK: - OAuth device flow (browser sign-in)

    /// Real-Debrid's open-source device-code client id (used by their own apps).
    private static let oauthClientID = "X245A4XAIBGVM"
    private static let oauthBase = "https://api.real-debrid.com/oauth/v2"

    /// Step 1: request a device + user code. The user visits the verification URL,
    /// signs in, and enters the code — same pattern as the Trakt browser flow.
    func requestDeviceCode() async throws -> RDDeviceCode {
        var comps = URLComponents(string: "\(Self.oauthBase)/device/code")!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: Self.oauthClientID),
            URLQueryItem(name: "new_credentials", value: "yes")
        ]
        let (data, _) = try await session.data(from: comps.url!)
        return try decoder.decode(RDDeviceCode.self, from: data)
    }

    /// Step 2: poll until the user authorizes. Returns nil while still pending.
    func pollForCredentials(deviceCode: String) async throws -> RDCredentials? {
        var comps = URLComponents(string: "\(Self.oauthBase)/device/credentials")!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: Self.oauthClientID),
            URLQueryItem(name: "code", value: deviceCode)
        ]
        let (data, response) = try await session.data(from: comps.url!)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            return nil   // still pending
        }
        return try? decoder.decode(RDCredentials.self, from: data)
    }

    /// Step 3: exchange the device code + obtained client credentials for a token.
    func obtainToken(clientID: String, clientSecret: String, deviceCode: String) async throws -> String {
        var req = URLRequest(url: URL(string: "\(Self.oauthBase)/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "client_id": clientID,
            "client_secret": clientSecret,
            "code": deviceCode,
            "grant_type": "http://oauth.net/grant_type/device/1.0"
        ].map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? $0.value)" }
         .joined(separator: "&")
        req.httpBody = body.data(using: .utf8)
        let (data, _) = try await session.data(for: req)
        let token = try decoder.decode(RDToken.self, from: data)
        return token.accessToken
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
        // FIX: apply the 30s timeout per-request (see init — the old configuration
        // mutation never took effect).
        req.timeoutInterval = 30
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
