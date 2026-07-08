//
//  OfflineCatalogCache.swift
//  Astra
//
//  Persistent caches for catalog content, so Home/Discover and detail screens can
//  show last-known data on a cold launch even when TMDB, Trakt, or addons are slow
//  or unreachable. Both caches are thin wrappers over the shared generic
//  DiskJSONCache, which owns the file handling, timestamps, and max-age logic.
//

import Foundation

/// Cache for shelf contents keyed by shelf cache key. A generous max age means
/// stale-but-useful content is shown offline rather than an empty screen; fresh
/// data overwrites it as soon as the network responds.
actor OfflineCatalogCache {
    static let shared = OfflineCatalogCache()

    private let cache = DiskJSONCache<[CatalogItem]>(
        folder: "OfflineCatalog", filePrefix: "shelf_",
        maxAge: 60 * 60 * 24 * 7    // 7 days
    )

    /// Persists a shelf's items under its cache key (no-op for empty results).
    func store(_ items: [CatalogItem], for key: String) async {
        guard !items.isEmpty else { return }
        await cache.store(items, for: key)
    }

    /// Returns cached items for a key if present and not past the max age.
    func items(for key: String) async -> [CatalogItem]? {
        await cache.value(for: key)
    }

    /// Clears all persisted shelf caches.
    func clear() async {
        await cache.clear()
    }
}

/// Persistent cache for hydrated single titles (with seasons/episodes/description),
/// so a previously-opened show still shows its details offline.
actor OfflineMetadataCache {
    static let shared = OfflineMetadataCache()

    private let cache = DiskJSONCache<CatalogItem>(
        folder: "OfflineMetadata", filePrefix: "meta_",
        maxAge: 60 * 60 * 24 * 30   // 30 days (metadata is stable)
    )

    func store(_ item: CatalogItem, for key: String) async {
        await cache.store(item, for: key)
    }

    func item(for key: String) async -> CatalogItem? {
        await cache.value(for: key)
    }

    func clear() async {
        await cache.clear()
    }
}
