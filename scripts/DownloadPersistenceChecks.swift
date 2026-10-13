// Compile with production CodableFileStore, LibraryFilePolicy and MediaReliabilityPolicy.
// Cloud transport is isolated; no user defaults, live networking, or app data is used.
import Foundation
import Combine

@MainActor final class CloudSync {
    static let shared = CloudSync()
    let externalChange = PassthroughSubject<[String], Never>()
    var values: [String: Data] = [:]
    func data(forKey key: String) -> Data? { values[key] }
    func setData(_ data: Data, forKey key: String) { values[key] = data }
}

@main struct DownloadPersistenceChecks {
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CodableFileStore<[Int]>(filename: "downloads.json", directory: root,
            validate: { Set($0).count == $0.count })
        precondition(store.load() == nil && !store.needsRecovery)
        precondition(store.save([1, 2]) && store.load() == [1, 2])
        precondition(!store.save([1, 1]) && store.lastError != nil)
        precondition(store.save([1, 3]) && store.lastError == nil)
        let path = root.appendingPathComponent("downloads.json")
        let broken = Data("invalid-data".utf8); try broken.write(to: path)
        let corrupt = CodableFileStore<[Int]>(filename: "downloads.json", directory: root)
        precondition(corrupt.load() == nil && corrupt.needsRecovery && !corrupt.save([]))
        let retained = try Data(contentsOf: path); precondition(retained == broken)
        precondition(corrupt.resetRetainingOriginal([]) && corrupt.load() == [])
        let backups = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.contains(".recovery-") }
        precondition(backups.count == 1)
        let originalBackup = try Data(contentsOf: backups[0]); precondition(originalBackup == broken)
        try JSONEncoder().encode([4]).write(to: path)
        precondition(corrupt.load() == [4] && !corrupt.needsRecovery && corrupt.save([5]))
        let linked = root.appendingPathComponent("linked.json")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: path)
        precondition(MediaReliabilityPolicy.ownedFile(path, in: root))
        precondition(!MediaReliabilityPolicy.ownedFile(linked, in: root))
        let linkStore = CodableFileStore<[Int]>(filename: "linked.json", directory: root)
        precondition(linkStore.load() == nil && linkStore.needsRecovery && !linkStore.save([]))
        let big = root.appendingPathComponent("big.json")
        precondition(FileManager.default.createFile(atPath: big.path, contents: nil))
        let handle = try FileHandle(forWritingTo: big); try handle.truncate(atOffset: 16 * 1_024 * 1_024 + 1); try handle.close()
        let oversized = CodableFileStore<[Int]>(filename: "big.json", directory: root)
        precondition(oversized.load() == nil && oversized.needsRecovery)
        let blocker = root.appendingPathComponent("blocker"); try Data([0]).write(to: blocker)
        let unwritable = CodableFileStore<[Int]>(filename: "x.json", directory: blocker)
        precondition(!unwritable.save([1]) && unwritable.lastError != nil)
        let cloudKey = "fixture"
        CloudSync.shared.values[cloudKey] = try JSONEncoder().encode([8])
        let cloudFailure = CodableFileStore<[Int]>(filename: "x.json", cloudKey: cloudKey, directory: blocker)
        precondition(cloudFailure.load() == nil && cloudFailure.lastError != nil)
        for value in ["ftp://example.invalid/movie.mp4", "https://example.invalid/list.M3U8", "https://example.invalid/stream.mpd"] {
            precondition(!MediaReliabilityPolicy.downloadableURL(URL(string: value)!))
        }
        precondition(MediaReliabilityPolicy.downloadableURL(URL(string: "https://example.invalid/movie.mp4")!))
        precondition(!MediaReliabilityPolicy.downloadableURL(URL(fileURLWithPath: "/fixture/list.m3u8")))
        for mime in ["text/html", "application/json", "application/dash+xml", "application/vnd.apple.mpegurl", "TEXT/XML"] {
            precondition(!MediaReliabilityPolicy.downloadableMIME(mime))
        }
        precondition(MediaReliabilityPolicy.downloadableMIME("video/mp4") && MediaReliabilityPolicy.downloadableMIME(nil))
        for ext in ["../bad", "../../mp4", "a/b", String(repeating: "x", count: 17), ""] {
            precondition(MediaReliabilityPolicy.downloadExtension(ext) == "media")
        }
        precondition(MediaReliabilityPolicy.downloadExtension("MP4") == "mp4")
        for age in [-1.0, Double.nan, Double.infinity] { precondition(MediaReliabilityPolicy.cleanupAge(age) == nil) }
        precondition(MediaReliabilityPolicy.cleanupAge(0) == 0)
        precondition(MediaReliabilityPolicy.downloadProgress(received: .min, expected: 100) == 0)
        precondition(MediaReliabilityPolicy.downloadProgress(received: .max, expected: 1) == 1)
        precondition(MediaReliabilityPolicy.downloadProgress(received: 20, expected: -1) == 0)
        print("PASS: isolated download persistence, recovery, bounded/symlink reads, validation, cloud commit failure, source/MIME/extension/age/progress policies")
    }
}
