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
}
