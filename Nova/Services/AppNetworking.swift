import SowensKit
//
//  AppNetworking.swift
//  Nova
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
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCredentialStorage = nil

        return URLSession(configuration: config)
    }()

    // MARK: - Shared request helpers

    enum RequestError: Error { case badStatus(Int, retryAfter: TimeInterval?), invalidResponse }

    /// Shared in-flight GETs avoid sending the same metadata request multiple times
    /// when several shelves become visible together.
    private actor GETCoalescer {
        var tasks: [URLRequest: Task<(Data, URLResponse), Error>] = [:]

        func data(for request: URLRequest, session: URLSession) async throws -> (Data, URLResponse) {
            try Task.checkCancellation()
            if let task = tasks[request] {
                let value = try await task.value
                try Task.checkCancellation()
                return value
            }
            let task = Task { try await session.sowensData(for: request) }
            tasks[request] = task
            defer { tasks[request] = nil }
            let value = try await task.value
            try Task.checkCancellation()
            return value
        }
    }
    private static let getCoalescer = GETCoalescer()

    /// Connectivity failures that may be answered from the response cache.
    private static let offlineFallbackCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .timedOut,
        .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .dataNotAllowed
    ]

    /// Supports delta seconds and HTTP dates, ignoring invalid/non-finite values.
    static func retryAfterSeconds(_ http: HTTPURLResponse) -> TimeInterval? {
        MediaReliabilityPolicy.retryAfter(http.value(forHTTPHeaderField: "Retry-After"))
    }

    /// GETs a URL and decodes JSON — the request/status-check/decode boilerplate
    /// previously reimplemented by each API client.
    static func getJSON<T: Decodable>(_ url: URL,
                                      timeout: TimeInterval = 20,
                                      headers: [String: String] = [:],
                                      decoder: JSONDecoder = Coders.decoder) async throws -> T {
        var req = URLRequest(url: url)
        req.timeoutInterval = MediaReliabilityPolicy.boundedInterval(timeout, fallback: 20)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await getCoalescer.data(for: req, session: shared)
        } catch let error as URLError where offlineFallbackCodes.contains(error.code) {
            // Offline or unreachable: serve the last successful response for this
            // exact request from the shared URL cache (stale-if-error), so catalog
            // and metadata screens keep their content instead of going blank.
            guard let cached = shared.configuration.urlCache?.cachedResponse(for: req),
                  let http = cached.response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw error }
            (data, response) = (cached.data, cached.response)
        }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw RequestError.invalidResponse }
        if !(200..<300).contains(http.statusCode) {
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
        try Task.checkCancellation()
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try Coders.encoder.encode(body)
        req.timeoutInterval = MediaReliabilityPolicy.boundedInterval(timeout, fallback: 30)
        let (data, response) = try await shared.sowensData(for: req)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw RequestError.invalidResponse }
        if !(200..<300).contains(http.statusCode) {
            throw RequestError.badStatus(http.statusCode, retryAfter: retryAfterSeconds(http))
        }
        return try decoder.decode(T.self, from: data)
    }
}
