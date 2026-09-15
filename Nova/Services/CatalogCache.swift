//
//  CatalogCache.swift
//  Nova
//
//  In-memory caches with a time-to-live for two expensive operations:
//    - Hydrated series/movie metadata (TMDB season/episode fan-out).
//    - Ranked stream lists per content id (addon fan-out).
//
//  These make reopening a show or an episode's stream list feel instant within a
//  session, while still refreshing after the TTL so data doesn't go stale.
//

import Foundation

/// Shared caches used by CatalogService.
enum CatalogCaches {
    /// Hydrated CatalogItems keyed by their stable content key. Metadata changes
    /// rarely, so a longer TTL is fine.
    static let metadata = TTLCache<String, CatalogItem>(ttl: 60 * 30)   // 30 min

    /// Ranked stream lists keyed by the Stremio id. Streams change more often and
    /// availability is time-sensitive, so a short TTL.
    static let streams = TTLCache<String, [StreamOption]>(ttl: 60 * 3)   // 3 min
}
