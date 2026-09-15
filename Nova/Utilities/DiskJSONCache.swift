import Foundation
import CryptoKit

/// Disposable, bounded offline metadata. The user's library is stored elsewhere.
actor DiskJSONCache<Value: Codable & Sendable> {
    private let directory: URL
    private let filePrefix: String
    private let maxAge: TimeInterval
    private let maxEntryBytes: Int
    private let maxDiskBytes: Int
    private let maxEntries: Int
    private let now: @Sendable () -> Date
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private struct Entry: Codable {
        let value: Value
        let storedAt: Date
    }

    init(folder: String, filePrefix: String, maxAge: TimeInterval,
         rootDirectory: URL? = nil, maxEntryBytes: Int = 8 * 1024 * 1024,
         maxDiskBytes: Int = 96 * 1024 * 1024, maxEntries: Int = 1024,
         now: @escaping @Sendable () -> Date = { Date() }) {
        let caches = rootDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directory = caches.appendingPathComponent(folder, isDirectory: true)
        self.filePrefix = filePrefix
        self.maxAge = maxAge.isFinite ? max(0, maxAge) : 0
        self.maxEntryBytes = max(1, min(maxEntryBytes, 64 * 1024 * 1024))
        self.maxDiskBytes = max(1, min(maxDiskBytes, 1024 * 1024 * 1024))
        self.maxEntries = max(1, min(maxEntries, 10_000))
        self.now = now
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        encoder = enc
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        decoder = dec
    }

    func store(_ value: Value, for key: String) {
        guard !Task.isCancelled,
              let data = try? encoder.encode(Entry(value: value, storedAt: now())),
              data.count <= min(maxEntryBytes, maxDiskBytes) else { return }
        do {
            // Caches may be purged by the OS while Nova is running.
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL(for: key), options: .atomic)
            prune()
        } catch { /* A cache failure never blocks local library operations. */ }
    }

    func value(for key: String, legacyValidator: (@Sendable (Value) -> Bool)? = nil) -> Value? {
        guard !Task.isCancelled else { return nil }
        let destination = fileURL(for: key)
        var url = destination
        if !isOwnedRegularFile(url), legacyValidator != nil {
            let safe = key.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }.joined()
            let name = filePrefix + safe + ".json"
            guard name.utf8.count <= 255 else { return nil }
            url = directory.appendingPathComponent(name)
        }
        guard isOwnedRegularFile(url) else { return nil }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0, size <= maxEntryBytes,
              let handle = try? FileHandle(forReadingFrom: url) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        defer { try? handle.close() }
        // Bound the actual read as well as stat; a concurrent writer can change size.
        guard let data = try? handle.read(upToCount: maxEntryBytes + 1), data.count <= maxEntryBytes,
              let entry = try? decoder.decode(Entry.self, from: data) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        let age = now().timeIntervalSince(entry.storedAt)
        guard age.isFinite, age >= -300, age < maxAge else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        if url != destination {
            // Only a domain owner can disambiguate a legacy filename by inspecting
            // the decoded identity. Copy the original timestamp, never extend TTL.
            guard legacyValidator?(entry.value) == true else { return nil }
            do {
                try data.write(to: destination, options: .atomic)
                try FileManager.default.removeItem(at: url)
                prune()
            } catch { /* The validated offline value is still usable. */ }
        }
        try? FileManager.default.setAttributes([.modificationDate: now()], ofItemAtPath: destination.path)
        return entry.value
    }

    func clear() {
        for url in ownedFiles() { try? FileManager.default.removeItem(at: url) }
    }

    /// Old punctuation-replaced keys were ambiguous and could exceed NAME_MAX.
    /// v2 uses the exact UTF-8 key. Legacy migration requires a domain identity
    /// validator; unknown cache ownership must never be guessed.
    private func fileURL(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(filePrefix + "v2_" + digest + ".json")
    }

    private func isOwnedRegularFile(_ url: URL) -> Bool {
        guard url.lastPathComponent.hasPrefix(filePrefix), url.pathExtension == "json",
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    private func ownedFiles() -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        return ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? [])
            .filter { isOwnedRegularFile($0) }
    }

    private struct File { let url: URL; let size: Int; let touched: Date }

    private func prune() {
        var files: [File] = []
        for url in ownedFiles() {
            guard let info = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { continue }
            let size = info.fileSize ?? 0
            let date = info.contentModificationDate ?? .distantPast
            if size > maxEntryBytes || now().timeIntervalSince(date) >= maxAge {
                try? FileManager.default.removeItem(at: url)
            } else { files.append(File(url: url, size: size, touched: date)) }
        }
        files.sort { $0.touched == $1.touched ? $0.url.lastPathComponent < $1.url.lastPathComponent : $0.touched < $1.touched }
        var bytes = files.reduce(Int64(0)) { $0 + Int64($1.size) }
        var count = files.count
        for file in files where bytes > Int64(maxDiskBytes) || count > maxEntries {
            do {
                try FileManager.default.removeItem(at: file.url)
                bytes -= Int64(file.size); count -= 1
            } catch { continue }
        }
    }
}

/// Hydration may add IMDb while a cache was originally keyed by TMDB/Trakt.
/// Validate all explicit provider identities, never title text or an unknown key.
enum MetadataCacheIdentity {
    static func matches(_ key: String, type: String, imdb: String?, tmdb: Int?, trakt: Int?, addon: String?) -> Bool {
        guard ["movie", "series", "tv"].contains(type) else { return false }
        if let imdb, !imdb.isEmpty, key == "imdb:\(imdb)" { return true }
        if let tmdb, tmdb > 0, key == "tmdb:\(type):\(tmdb)" { return true }
        if let trakt, trakt > 0, key == "trakt:\(type):\(trakt)" { return true }
        if let addon, !addon.isEmpty, key == "addon:\(type):\(addon)" { return true }
        return false
    }
}
