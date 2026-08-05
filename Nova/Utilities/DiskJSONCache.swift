//
//  DiskJSONCache.swift
//  Nova
//
//  A generic disk-backed JSON cache with per-entry timestamps and a max age.
//  Unifies the hand-rolled disk caching previously duplicated by the offline
//  catalog and metadata caches: one tested implementation, many value types.
//

import Foundation

actor DiskJSONCache<Value: Codable & Sendable> {
    private let directory: URL
    private let filePrefix: String
    private let maxAge: TimeInterval
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private struct Entry: Codable {
        let value: Value
        let storedAt: Date
    }

    init(folder: String, filePrefix: String, maxAge: TimeInterval) {
        let caches = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first!
        directory = caches.appendingPathComponent(folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.filePrefix = filePrefix
        self.maxAge = maxAge
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        encoder = enc
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        decoder = dec
    }

    /// Persists a value under a key with the current timestamp.
    func store(_ value: Value, for key: String) {
        let entry = Entry(value: value, storedAt: Date())
        if let data = try? encoder.encode(entry) {
            try? data.write(to: fileURL(for: key), options: [.atomic])
        }
    }

    /// Returns the cached value for a key if present and not past the max age.
    func value(for key: String) -> Value? {
        guard let data = try? Data(contentsOf: fileURL(for: key)),
              let entry = try? decoder.decode(Entry.self, from: data) else { return nil }
        if Date().timeIntervalSince(entry.storedAt) > maxAge { return nil }
        return entry.value
    }

    /// Removes every entry written by this cache (matching its file prefix).
    func clear() {
        guard let files = try? FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for f in files where f.lastPathComponent.hasPrefix(filePrefix) {
            try? FileManager.default.removeItem(at: f)
        }
    }

    /// A filesystem-safe filename for a cache key.
    private func fileURL(for key: String) -> URL {
        let safe = key.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "_"
        }
        return directory.appendingPathComponent(filePrefix + String(safe) + ".json")
    }
}
