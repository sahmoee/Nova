//
//  AppNetworking.swift
//  Astra
//
//  A single shared, tuned URLSession used across the app's network clients.
//  URLSession.shared has a small default cache and isn't configured for our usage;
//  one shared, well-configured session improves connection reuse (HTTP keep-alive),
//  caching, and timeouts versus several default sessions.
//

import Foundation

enum AppNetworking {

    /// Shared session for JSON/API traffic (TMDB, Trakt, addons, Real-Debrid, etc.).
    /// Images use their own dedicated session in ImageLoader.
    static let shared: URLSession = {
        let config = URLSessionConfiguration.default

        // A real on-disk response cache (the default is tiny). Many catalog/addon
        // responses are cacheable and this avoids re-fetching within and across runs.
        config.urlCache = URLCache(
            memoryCapacity: 16 * 1024 * 1024,     // 16 MB
            diskCapacity: 128 * 1024 * 1024,      // 128 MB
            directory: nil
        )
        config.requestCachePolicy = .useProtocolCachePolicy

        // Reuse connections aggressively and keep more sockets warm to the same hosts
        // (addons and metadata services are hit repeatedly in bursts). HTTP/2 and HTTP/3
        // multiplex automatically, so explicit pipelining is no longer set.
        config.httpMaximumConnectionsPerHost = 6
        config.waitsForConnectivity = true

        // Reasonable timeouts so a slow addon doesn't hang the whole fan-out.
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 45

        return URLSession(configuration: config)
    }()

    // MARK: - Shared request helpers

    enum RequestError: Error { case badStatus(Int, retryAfter: TimeInterval?) }

    /// Parses a Retry-After header (integer seconds form) if present.
    static func retryAfterSeconds(_ http: HTTPURLResponse) -> TimeInterval? {
        guard let v = http.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespaces),
              let secs = TimeInterval(v) else { return nil }
        return max(0, secs)
    }

    /// GETs a URL and decodes JSON — the request/status-check/decode boilerplate
    /// previously reimplemented by each API client.
    static func getJSON<T: Decodable>(_ url: URL,
                                      timeout: TimeInterval = 20,
                                      headers: [String: String] = [:],
                                      decoder: JSONDecoder = Coders.decoder) async throws -> T {
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw RequestError.badStatus(http.statusCode, retryAfter: retryAfterSeconds(http))
        }
        return try decoder.decode(T.self, from: data)
    }

    /// POSTs an Encodable JSON body and decodes the JSON response.
    static func postJSON<Body: Encodable, T: Decodable>(_ url: URL,
                                                        body: Body,
                                                        timeout: TimeInterval = 30,
                                                        headers: [String: String] = [:],
                                                        decoder: JSONDecoder = Coders.decoder) async throws -> T {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try Coders.encoder.encode(body)
        req.timeoutInterval = timeout
        let (data, response) = try await shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw RequestError.badStatus(http.statusCode, retryAfter: retryAfterSeconds(http))
        }
        return try decoder.decode(T.self, from: data)
    }
}
