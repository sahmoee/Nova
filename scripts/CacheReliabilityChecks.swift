import Foundation

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Double
    init(_ value: Double) { self.value = value }
    func get() -> Double { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ delta: Double) { lock.lock(); value += delta; lock.unlock() }
}
private actor Gate {
    private var continuation: CheckedContinuation<Int, Never>?
    private var started = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func load() async -> Int {
        started = true
        waiters.forEach { $0.resume() }; waiters.removeAll()
        return await withCheckedContinuation { continuation = $0 }
    }
    func waitForStart() async {
        if started { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func finish(_ value: Int) { continuation?.resume(returning: value); continuation = nil }
}
@main
struct CacheReliabilityChecks {
    static var count = 0
    static func check(_ value: Bool, _ message: String) { precondition(value, message); count += 1 }
    static func main() async throws {
        let clock = Clock(100)
        let ttl = TTLCache<String, Int>(ttl: 10, maxEntries: 2, now: { clock.get() })
        await ttl.set(1, for: "a"); await ttl.set(2, for: "b")
        check(await ttl.value(for: "a") == 1, "TTL round trip")
        await ttl.set(3, for: "c")
        check(await ttl.value(for: "b") == nil, "Evict least recently read")
        check(await ttl.value(for: "a") == 1, "Reading retains hot entry")
        await ttl.set(4, for: "a")
        check(await ttl.value(for: "c") == 3, "Replacing must not evict another key")
        check(await ttl.value(for: "a") == 4, "Replacement stored")
        clock.advance(10)
        check(await ttl.value(for: "a") == nil, "Exact monotonic TTL expires")
        check(await ttl.staleValue(for: "a") == 4, "Explicit stale fallback remains")
        let one = TTLCache<String, Int>(ttl: 60, maxEntries: 0)
        await one.set(1, for: "one"); await one.set(2, for: "two")
        check(await one.value(for: "one") == nil, "Zero capacity clamps and stays bounded")
        check(await one.value(for: "two") == 2, "Small cache keeps latest")
        let invalid = TTLCache<String, Int>(ttl: .nan)
        await invalid.set(1, for: "a")
        check(await invalid.value(for: "a") == nil, "NaN TTL never becomes immortal")

        let coalescing = TTLCache<String, Int>(ttl: 60)
        let oldGate = Gate(), newGate = Gate()
        let old = Task { await coalescing.coalesced(for: "a", shouldCache: { _ in true }) { await oldGate.load() } }
        await oldGate.waitForStart()
        await coalescing.removeAll()
        let fresh = Task { await coalescing.coalesced(for: "a", shouldCache: { _ in true }) { await newGate.load() } }
        await newGate.waitForStart()
        await oldGate.finish(1)
        check(await old.value == 1, "Retired caller completes without hanging")
        check(await coalescing.value(for: "a") == nil, "Retired producer cannot repopulate reset cache")
        await newGate.finish(2)
        check(await fresh.value == 2, "Replacement flight survives old completion")
        check(await coalescing.value(for: "a") == 2, "Only live flight publishes")
        check(await coalescing.coalesced(for: "a") { 99 } == 2, "Late miss rechecks cache")
        _ = await coalescing.coalesced(for: "empty", shouldCache: { $0 != 0 }) { 0 }
        check(await coalescing.value(for: "empty") == nil, "Failed/empty response stays retryable")
        await coalescing.removeAll()
        check(await coalescing.staleValue(for: "a") == nil, "Reset clears stale cache too")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NovaCacheChecks-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let wall = Clock(Date().timeIntervalSince1970)
        let disk = DiskJSONCache<String>(folder: "test", filePrefix: "a_", maxAge: 60, rootDirectory: root, now: { Date(timeIntervalSince1970: wall.get()) })
        await disk.store("colon", for: "tmdb:123")
        await disk.store("slash", for: "tmdb/123")
        check(await disk.value(for: "tmdb:123") == "colon", "Punctuation keys never collide")
        check(await disk.value(for: "tmdb/123") == "slash", "Both collision fixtures survive")
        let hugeKey = String(repeating: "電影🎬/:?", count: 5000)
        await disk.store("long", for: hugeKey)
        check(await disk.value(for: hugeKey) == "long", "Long Unicode key remains filesystem-safe")
        let files = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("test"), includingPropertiesForKeys: nil)
        check(files.allSatisfy { $0.lastPathComponent.utf8.count < 100 }, "Fixed length filenames")
        wall.advance(61)
        check(await disk.value(for: "tmdb:123") == nil, "Timestamp expiry")
        check(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("test").path).count == 2, "Expired payload physically removed")
        await disk.clear()
        await disk.store("future", for: "future")
        wall.advance(-1000)
        check(await disk.value(for: "future") == nil, "Far-future timestamp rejected")
        await disk.clear()
        try FileManager.default.removeItem(at: root.appendingPathComponent("test"))
        await disk.store("recovered", for: "after-purge")
        check(await disk.value(for: "after-purge") == "recovered", "OS directory purge repairs on next store")
        let corrupt = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("test"), includingPropertiesForKeys: nil).first!
        try Data("broken JSON".utf8).write(to: corrupt)
        check(await disk.value(for: "after-purge") == nil, "Corrupt cache returns a miss")
        check(!FileManager.default.fileExists(atPath: corrupt.path), "Corrupt payload removed")

        // Preserve identity-validated metadata without guessing a colliding shelf key.
        let legacy = root.appendingPathComponent("test/a_ref_1.json")
        let formatter = ISO8601DateFormatter()
        let legacyBytes = try JSONSerialization.data(withJSONObject: ["value": "legacy-ref-1", "storedAt": formatter.string(from: Date(timeIntervalSince1970: wall.get()))])
        try legacyBytes.write(to: legacy)
        check(await disk.value(for: "ref/1") == nil, "Legacy migration requires explicit identity validation")
        check(await disk.value(for: "ref/1", legacyValidator: { $0 == "other-ref" }) == nil, "Legacy collision never accepted for wrong identity")
        check(FileManager.default.fileExists(atPath: legacy.path), "Rejected legacy entry preserved for its actual owner")
        check(await disk.value(for: "ref:1", legacyValidator: { $0 == "legacy-ref-1" }) == "legacy-ref-1", "Validated metadata remains available offline")
        check(!FileManager.default.fileExists(atPath: legacy.path), "Successful migration removes only its old file")
        check(await disk.value(for: "ref:1") == "legacy-ref-1", "Migrated exact key readable without validator")
        wall.advance(61)
        check(await disk.value(for: "ref:1") == nil, "Migration preserves original timestamp")

        check(MetadataCacheIdentity.matches("tmdb:series:123", type: "series", imdb: "tt456", tmdb: 123, trakt: nil, addon: nil), "TMDB legacy key survives IMDb enrichment")
        check(MetadataCacheIdentity.matches("imdb:tt456", type: "series", imdb: "tt456", tmdb: 123, trakt: nil, addon: nil), "IMDb alias still recognized")
        check(MetadataCacheIdentity.matches("trakt:movie:789", type: "movie", imdb: "tt456", tmdb: 123, trakt: 789, addon: nil), "Trakt alias survives enrichment")
        check(!MetadataCacheIdentity.matches("tmdb:movie:123", type: "series", imdb: "tt456", tmdb: 123, trakt: nil, addon: nil), "Numeric ID requires correct content type")
        check(!MetadataCacheIdentity.matches("tmdb:series:124", type: "series", imdb: "tt456", tmdb: 123, trakt: nil, addon: nil), "Different numeric ID rejected")
        check(!MetadataCacheIdentity.matches("unknown:series", type: "series", imdb: nil, tmdb: nil, trakt: nil, addon: nil), "Unknown identity never authorizes migration")
        check(MetadataCacheIdentity.matches("addon:tv:channel/name", type: "tv", imdb: nil, tmdb: nil, trakt: nil, addon: "channel/name"), "Exact addon identity preserved")

        let bounded = DiskJSONCache<String>(folder: "bounded", filePrefix: "b_", maxAge: 60, rootDirectory: root, maxEntryBytes: 100, maxDiskBytes: 180, maxEntries: 2)
        await bounded.store(String(repeating: "x", count: 150), for: "big")
        check(await bounded.value(for: "big") == nil, "Encoded payload size limit")
        for n in 0..<10 { await bounded.store(String(n), for: String(n)) }
        let boundedFiles = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("bounded"), includingPropertiesForKeys: [.fileSizeKey])
        check(boundedFiles.count <= 2, "Hard entry budget")
        check(try boundedFiles.reduce(0) { $0 + (try $1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) } <= 180, "Hard byte budget")
        let newest = boundedFiles.first!
        try Data(repeating: 65, count: 101).write(to: newest)
        // Read both keys so the altered file is encountered, independent of LRU ordering.
        _ = await bounded.value(for: "8"); _ = await bounded.value(for: "9")
        check(!FileManager.default.fileExists(atPath: newest.path), "Oversized disk replacement rejected before decode")

        let a = DiskJSONCache<Int>(folder: "shared", filePrefix: "a_", maxAge: 60, rootDirectory: root)
        let b = DiskJSONCache<Int>(folder: "shared", filePrefix: "b_", maxAge: 60, rootDirectory: root)
        await a.store(1, for: "key"); await b.store(2, for: "key")
        let shared = root.appendingPathComponent("shared")
        let other = shared.appendingPathComponent("a_notes.txt")
        try Data("keep".utf8).write(to: other)
        let directory = shared.appendingPathComponent("a_folder.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let link = shared.appendingPathComponent("a_link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: other)
        await a.clear()
        check(await b.value(for: "key") == 2, "Clear isolates peer prefix")
        check(FileManager.default.fileExists(atPath: other.path), "Clear retains non-JSON files")
        check(FileManager.default.fileExists(atPath: directory.path), "Clear never removes directories")
        check(FileManager.default.fileExists(atPath: link.path), "Clear never follows symlinks")

        check(ArtworkCachePolicy.pixels(.nan) == 600, "NaN pixels normalize")
        check(ArtworkCachePolicy.pixels(.infinity) == 600, "Infinite pixels normalize")
        check(ArtworkCachePolicy.pixels(-1) == 600, "Negative pixels normalize")
        check(ArtworkCachePolicy.pixels(.greatestFiniteMagnitude) == 4096, "Huge pixels bounded before Int conversion")
        check(ArtworkCachePolicy.pixels(0.1) == 64, "Tiny pixels clamped")
        check(ArtworkCachePolicy.pixels(700.1) == 701, "Fractional pixels round up")
        let url = URL(string: "https://example.invalid/poster#one")!
        let second = URL(string: "https://example.invalid/poster#one#600")!
        check(ArtworkCachePolicy.key(url: url, pixels: 600) != ArtworkCachePolicy.key(url: second, pixels: 600), "URL fragment belongs to stable identity")
        check(ArtworkCachePolicy.key(url: url, pixels: 600) != ArtworkCachePolicy.key(url: url, pixels: 800), "Size belongs to stable identity")
        check(ArtworkCachePolicy.decodedCost(width: Int.max, height: Int.max) == nil, "Pixel-cost overflow rejected")
        check(ArtworkCachePolicy.decodedCost(width: 700, height: 1000) == 2_800_000, "Decoded byte accounting")
        check(ArtworkCachePolicy.decodedCost(width: 0, height: 100) == nil, "Empty image rejected")
        print("PASS: \(count) cache reliability checks")
    }
}
