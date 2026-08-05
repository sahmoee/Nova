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

/// A simple generic TTL cache, actor-isolated for safe concurrent access.
actor TTLCache<Key: Hashable & Sendable, Value: Sendable> {
    private struct Entry {
        let value: Value
        let expiry: Date
    }

    private var store: [Key: Entry] = [:]
    private var inFlight: [Key: Task<Value, Never>] = [:]
    private let ttl: TimeInterval
    private let maxEntries: Int

    init(ttl: TimeInterval, maxEntries: Int = 200) {
        self.ttl = ttl
        self.maxEntries = maxEntries
    }

    func value(for key: Key) -> Value? {
        guard let entry = store[key] else { return nil }
        if entry.expiry < Date() {
            return nil
        }
        return entry.value
    }

    /// Returns an entry even after expiry so UI can paint stale content immediately
    /// while a refresh happens in the background.
    func staleValue(for key: Key) -> Value? { store[key]?.value }

    /// Coalesces concurrent misses for the same key. The caller decides whether the
    /// result is meaningful enough to cache (for example, empty network fallbacks are
    /// often intentionally not cached).
    func coalesced(for key: Key,
                   loader: @escaping @Sendable () async -> Value) async -> Value {
        if let task = inFlight[key] { return await task.value }
        let task = Task { await loader() }
        inFlight[key] = task
        let value = await task.value
        inFlight[key] = nil
        return value
    }

    func set(_ value: Value, for key: Key) {
        if store.count >= maxEntries {
            // Drop the soonest-to-expire entries to make room.
            let sorted = store.sorted { $0.value.expiry < $1.value.expiry }
            for (k, _) in sorted.prefix(maxEntries / 4) { store[k] = nil }
        }
        store[key] = Entry(value: value, expiry: Date().addingTimeInterval(ttl))
    }

    func removeAll() {
        store.removeAll()
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
    }
}

/// Shared caches used by CatalogService.
enum CatalogCaches {
    /// Hydrated CatalogItems keyed by their stable content key. Metadata changes
    /// rarely, so a longer TTL is fine.
    static let metadata = TTLCache<String, CatalogItem>(ttl: 60 * 30)   // 30 min

    /// Ranked stream lists keyed by the Stremio id. Streams change more often and
    /// availability is time-sensitive, so a short TTL.
    static let streams = TTLCache<String, [StreamOption]>(ttl: 60 * 3)   // 3 min
}
