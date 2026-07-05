//
//  OfflineCatalogCache.swift
//  Astra
//
//  A small persistent cache for catalog shelf contents, written to disk so the home
//  and discover screens can show last-known titles on a cold launch even when TMDB,
//  Trakt, or addons are slow or unreachable. This complements the in-memory TTLCache,
//  which is fast within a session but lost on restart.
//
//  Entries are kept per shelf cache key. A generous max age means stale-but-useful
//  content is shown offline rather than an empty screen; fresh data overwrites it as
//  soon as the network responds.
//

import Foundation

actor OfflineCatalogCache {
    static let shared = OfflineCatalogCache()

    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    /// Beyond this age, cached shelves are ignored (they're likely too stale to show).
    private let maxAge: TimeInterval = 60 * 60 * 24 * 7   // 7 days

    private struct Entry: Codable {
        let items: [CatalogItem]
        let storedAt: Date
    }

    init() {
        let caches = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first!
        directory = caches.appendingPathComponent("OfflineCatalog", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        encoder = enc
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        decoder = dec
    }

    /// Persists a shelf's items under its cache key (no-op for empty results).
    func store(_ items: [CatalogItem], for key: String) {
        guard !items.isEmpty else { return }
        let entry = Entry(items: items, storedAt: Date())
        if let data = try? encoder.encode(entry) {
            try? data.write(to: fileURL(for: key), options: [.atomic])
        }
    }

    /// Returns cached items for a key if present and not past the max age.
    func items(for key: String) -> [CatalogItem]? {
        guard let data = try? Data(contentsOf: fileURL(for: key)),
              let entry = try? decoder.decode(Entry.self, from: data) else { return nil }
        if Date().timeIntervalSince(entry.storedAt) > maxAge { return nil }
        return entry.items
    }

    /// Clears all persisted shelf caches.
    func clear() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for f in files { try? FileManager.default.removeItem(at: f) }
    }

    /// A filesystem-safe filename for a cache key.
    private func fileURL(for key: String) -> URL {
        let safe = key.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "_"
        }
        return directory.appendingPathComponent("shelf_" + String(safe) + ".json")
    }
}

/// Persistent cache for hydrated single titles (with seasons/episodes/description),
/// so a previously-opened show still shows its details offline.
actor OfflineMetadataCache {
    static let shared = OfflineMetadataCache()

    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let maxAge: TimeInterval = 60 * 60 * 24 * 30   // 30 days (metadata is stable)

    private struct Entry: Codable {
        let item: CatalogItem
        let storedAt: Date
    }

    init() {
        let caches = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first!
        directory = caches.appendingPathComponent("OfflineMetadata", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        encoder = enc
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        decoder = dec
    }

    func store(_ item: CatalogItem, for key: String) {
        let entry = Entry(item: item, storedAt: Date())
        if let data = try? encoder.encode(entry) {
            try? data.write(to: fileURL(for: key), options: [.atomic])
        }
    }

    func item(for key: String) -> CatalogItem? {
        guard let data = try? Data(contentsOf: fileURL(for: key)),
              let entry = try? decoder.decode(Entry.self, from: data) else { return nil }
        if Date().timeIntervalSince(entry.storedAt) > maxAge { return nil }
        return entry.item
    }

    func clear() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for f in files { try? FileManager.default.removeItem(at: f) }
    }

    private func fileURL(for key: String) -> URL {
        let safe = key.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "_"
        }
        return directory.appendingPathComponent("meta_" + String(safe) + ".json")
    }
}
