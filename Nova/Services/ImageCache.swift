//
//  ImageCache.swift
//  Nova
//
//  A lightweight two-tier image cache so posters and stills load instantly on
//  revisit instead of being re-downloaded every time (plain AsyncImage does no
//  persistent caching). Tier 1 is an in-memory NSCache of decoded UIImages; tier
//  2 is a disk-backed URLCache on a dedicated URLSession.
//

import SwiftUI
import ImageIO
import CryptoKit

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#endif

actor ImageLoader {
    static let shared = ImageLoader()

    private let session: URLSession
    private let memory = NSCache<NSString, PlatformImage>()
    private struct Flight { let id: UUID; let task: Task<PlatformImage?, Never> }
    private var inFlight: [String: Flight] = [:]
    private var failures: [String: TimeInterval] = [:]
    private var writesSincePrune = 0
    private var prefetchTask: Task<Void, Never>?
    private let diskDir: URL

    init() {
        // 50 MB memory + 200 MB disk URLCache dedicated to images.
        let cache = URLCache(memoryCapacity: 50 * 1024 * 1024,
                             diskCapacity: 200 * 1024 * 1024,
                             directory: nil)
        let config = URLSessionConfiguration.default
        config.urlCache = cache
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpMaximumConnectionsPerHost = 6
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCredentialStorage = nil
        session = URLSession(configuration: config)
        memory.countLimit = 400
        memory.totalCostLimit = 80 * 1024 * 1024   // ~80 MB of decoded pixels

        // Disk cache for *downsampled, decoded* images (separate from URLCache's raw
        // bytes) so revisits skip both the network and the decode/downsample work.
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        diskDir = caches.appendingPathComponent("nova-images", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDir, withIntermediateDirectories: true)

        // Evict stale/oversized decoded images in the background on launch so the
        // nova-images directory can't grow without bound.
        let dir = diskDir
        Task.detached(priority: .background) { ImageLoader.evictDiskCache(in: dir) }

        #if os(iOS) || os(tvOS)
        Task { @MainActor in
            // Discard the observer token: it's a lifetime-of-process singleton, and
            // ignoring the returned `any NSObjectProtocol` keeps this Task's result
            // `Void` (that non-Sendable token can't be the Task's success value).
            _ = NotificationCenter.default.addObserver(
                forName: UIApplication.didReceiveMemoryWarningNotification,
                object: nil, queue: .main) { _ in
                Task { await ImageLoader.shared.purgeMemory() }
            }
        }
        #endif
    }

    /// Clears the in-memory image cache; the disk cache is retained.
    func purgeMemory() {
        memory.removeAllObjects()
        prefetchTask?.cancel()
        prefetchTask = nil
        for flight in inFlight.values { flight.task.cancel() }
        inFlight.removeAll()
        failures.removeAll()
    }

    /// Loads an image, downsampled to roughly `maxPixel` on the long edge. Decoding a
    /// poster at thumbnail size instead of full resolution is dramatically faster and
    /// uses a fraction of the memory, which removes scroll hitches in grids.
    func image(for url: URL, maxPixel: CGFloat = 600) async -> PlatformImage? {
        guard !Task.isCancelled else { return nil }
        let pixels = ArtworkCachePolicy.pixels(maxPixel)
        let key = ArtworkCachePolicy.key(url: url, pixels: pixels)
        let nsKey = key as NSString
        if let cached = memory.object(forKey: nsKey) { return cached }
        let now = ProcessInfo.processInfo.systemUptime
        if let until = failures[key], until > now { return nil }
        if let existing = inFlight[key] {
            let result = await existing.task.value
            return Task.isCancelled || existing.task.isCancelled ? nil : result
        }

        let id = UUID()
        let task = Task<PlatformImage?, Never>.detached(priority: .utility) { [session, diskDir] in
            guard !Task.isCancelled else { return nil }
            let diskPath = diskDir.appendingPathComponent("v2_" + key + ".jpg")
            // The former image key is reconstructible for this exact URL and size;
            // preserve offline artwork without guessing legacy metadata-cache keys.
            let legacyURL = URL(string: url.absoluteString + "#\(pixels)") ?? url
            let legacyDigest = SHA256.hash(data: Data(legacyURL.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
            let legacyPath = diskDir.appendingPathComponent(legacyDigest + ".jpg")
            // Downsample cached files as well: corrupt/oversized replacements must
            // not take the UIImage full-resolution fallback path.
            for cachedPath in [diskPath, legacyPath] {
                if let info = try? cachedPath.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                   info.isRegularFile == true, info.isSymbolicLink != true,
                   let size = info.fileSize, size > 0, size <= ArtworkCachePolicy.maximumDownloadBytes,
                   let image = Self.downsample(file: cachedPath, maxPixel: pixels) {
                    try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: cachedPath.path)
                    return Task.isCancelled ? nil : image
                }
                // Cache files are disposable, but never recursively remove a foreign directory.
                if let info = try? cachedPath.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                   info.isRegularFile == true, info.isSymbolicLink != true {
                    try? FileManager.default.removeItem(at: cachedPath)
                }
            }
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            // Download to a temporary file rather than buffering an unchecked body
            // in RAM. The delegate cancels oversized transfers during receipt.
            guard !Task.isCancelled,
                  let (file, response) = try? await session.download(for: request, delegate: ArtworkDownloadLimit()) else { return nil }
            defer { try? FileManager.default.removeItem(at: file) }
            guard !Task.isCancelled,
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size > 0, size <= ArtworkCachePolicy.maximumDownloadBytes,
                  let image = Self.downsample(file: file, maxPixel: pixels) else { return nil }

            let hasAlpha: Bool
            switch image.cgImage?.alphaInfo {
            case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly: hasAlpha = true
            default: hasAlpha = false
            }
            guard !Task.isCancelled else { return nil }
            let encoded = hasAlpha ? image.pngData() : image.jpegData(compressionQuality: 0.85)
            if let encoded, !Task.isCancelled {
                try? FileManager.default.createDirectory(at: diskDir, withIntermediateDirectories: true)
                try? encoded.write(to: diskPath, options: .atomic)
            }
            return Task.isCancelled ? nil : image
        }
        inFlight[key] = Flight(id: id, task: task)
        let result = await task.value
        // A memory purge may have retired this flight and started a replacement.
        guard inFlight[key]?.id == id, !task.isCancelled else { return nil }
        inFlight[key] = nil
        if let result, let cg = result.cgImage,
           let cost = ArtworkCachePolicy.decodedCost(width: cg.width, height: cg.height) {
            memory.setObject(result, forKey: nsKey, cost: cost)
            failures[key] = nil
            writesSincePrune += 1
            if writesSincePrune >= 16 {
                writesSincePrune = 0
                let directory = diskDir
                Task.detached(priority: .background) { Self.evictDiskCache(in: directory) }
            }
        } else {
            // Prevent broken artwork from retrying on every grid re-evaluation.
            failures = failures.filter { $0.value > now }
            if failures.count >= 256, let oldest = failures.min(by: { $0.value < $1.value })?.key { failures[oldest] = nil }
            failures[key] = ProcessInfo.processInfo.systemUptime + 20
        }
        return Task.isCancelled ? nil : result
    }

    /// Warm the cache for a set of URLs (e.g. the next rows in a grid) so they're
    /// already decoded by the time they scroll on screen. Fire-and-forget.
    nonisolated func prefetch(_ urls: [URL], maxPixel: CGFloat = 600) {
        Task(priority: .utility) { await self.schedulePrefetch(urls, maxPixel: maxPixel) }
    }

    private func schedulePrefetch(_ urls: [URL], maxPixel: CGFloat) {
        // Build a bounded eager array. A stateful LazyFilterSequence combined with
        // prefix could be evaluated re-entrantly by concurrent callers and crash in
        // Swift's range implementation. Eager de-duplication is deterministic and
        // never asks the lazy collection for unstable indices.
        var seen = Set<URL>()
        var queue: [URL] = []
        queue.reserveCapacity(min(16, urls.count))
        for url in urls where queue.count < 16 {
            if seen.insert(url).inserted { queue.append(url) }
        }
        prefetchTask?.cancel()
        prefetchTask = Task(priority: .utility) { [queue] in
            await withTaskGroup(of: Void.self) { group in
                var iterator = queue.makeIterator()
                for _ in 0..<min(4, queue.count) {
                    if let url = iterator.next() {
                        group.addTask { _ = await self.image(for: url, maxPixel: maxPixel) }
                    }
                }
                while await group.next() != nil {
                    guard !Task.isCancelled else { group.cancelAll(); return }
                    if let url = iterator.next() {
                        group.addTask { _ = await self.image(for: url, maxPixel: maxPixel) }
                    }
                }
            }
        }
    }

    // Disk-cache eviction budget for the decoded-image directory.
    private static let maxDiskAge: TimeInterval = 14 * 24 * 3600   // 14 days
    private static let maxDiskBytes: Int = 300 * 1024 * 1024       // 300 MB

    /// Removes decoded images that are too old, then, if still over budget, deletes the
    /// least-recently-used files until under the size cap. Runs off the actor.
    nonisolated static func evictDiskCache(in dir: URL) {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys,
                                                      options: [.skipsHiddenFiles]) else { return }
        let now = Date()
        struct Entry { let url: URL; let date: Date; let size: Int }
        var entries: [Entry] = []
        for u in items {
            guard u.pathExtension == "jpg",
                  let v = try? u.resourceValues(forKeys: Set(keys)),
                  v.isRegularFile == true, v.isSymbolicLink != true else { continue }
            let date = v.contentModificationDate ?? .distantPast
            let size = v.totalFileAllocatedSize ?? v.fileSize ?? 0
            // 1) Age-based removal.
            if now.timeIntervalSince(date) > maxDiskAge {
                try? fm.removeItem(at: u)
            } else {
                entries.append(Entry(url: u, date: date, size: size))
            }
        }
        // 2) Size-based LRU removal.
        var total = entries.reduce(0) { $0 + $1.size }
        guard total > maxDiskBytes else { return }
        for e in entries.sorted(by: { $0.date < $1.date }) {   // oldest first
            do { try fm.removeItem(at: e.url); total -= e.size } catch { continue }
            if total <= maxDiskBytes { break }
        }
    }

    /// Downsamples image data to `maxPixel` on the long edge using ImageIO, which
    /// decodes directly at the target size rather than allocating the full image.
    private static func downsample(file: URL, maxPixel: Int) -> PlatformImage? {
        let srcOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithURL(file as CFURL, srcOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
            return nil
        }
        return PlatformImage(cgImage: cg)
    }
}

/// Cancels a response once its advertised or received size exceeds the artwork budget.
private final class ArtworkDownloadLimit: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let limit = Int64(ArtworkCachePolicy.maximumDownloadBytes)
        if totalBytesWritten > limit || totalBytesExpectedToWrite > limit { downloadTask.cancel() }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
}

/// Shared artwork phase: a retired request can never paint over a recycled card.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    var maxPixel: CGFloat = 600
    @ViewBuilder var content: (Image) -> Content
    @ViewBuilder var placeholder: () -> Placeholder
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var loaded: PlatformImage?
    @State private var loadedIdentity: LoadIdentity?
    @State private var requestID = UUID()

    private var identity: LoadIdentity { LoadIdentity(url: url, pixels: ArtworkCachePolicy.pixels(maxPixel)) }

    var body: some View {
        Group {
            if let loaded, loadedIdentity == identity {
                content(Image(uiImage: loaded).interpolation(.high).antialiased(true))
                    .transition(reduceMotion ? .identity : .opacity)
            } else {
                placeholder().transition(reduceMotion ? .identity : .opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: loadedIdentity)
        .task(id: identity) {
            let expected = identity
            let token = UUID()
            requestID = token
            loaded = nil
            loadedIdentity = nil
            guard let url = expected.url else { return }
            let image = await ImageLoader.shared.image(for: url, maxPixel: CGFloat(expected.pixels))
            guard !Task.isCancelled, requestID == token else { return }
            loaded = image
            loadedIdentity = image == nil ? nil : expected
        }
    }

    private struct LoadIdentity: Hashable {
        let url: URL?
        let pixels: Int
    }
}
