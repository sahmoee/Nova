//
//  ImageCache.swift
//  Astra
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
    private let memory = NSCache<NSURL, PlatformImage>()
    private var inFlight: [URL: Task<PlatformImage?, Never>] = [:]
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
        session = URLSession(configuration: config)
        memory.countLimit = 400
        memory.totalCostLimit = 80 * 1024 * 1024   // ~80 MB of decoded pixels

        // Disk cache for *downsampled, decoded* images (separate from URLCache's raw
        // bytes) so revisits skip both the network and the decode/downsample work.
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        diskDir = caches.appendingPathComponent("astra-images", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDir, withIntermediateDirectories: true)

        // Evict stale/oversized decoded images in the background on launch so the
        // astra-images directory can't grow without bound.
        let dir = diskDir
        Task.detached(priority: .background) { ImageLoader.evictDiskCache(in: dir) }

        #if os(iOS)
        Task { @MainActor in
            NotificationCenter.default.addObserver(
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
    }

    /// Loads an image, downsampled to roughly `maxPixel` on the long edge. Decoding a
    /// poster at thumbnail size instead of full resolution is dramatically faster and
    /// uses a fraction of the memory, which removes scroll hitches in grids.
    func image(for url: URL, maxPixel: CGFloat = 600) async -> PlatformImage? {
        let key = cacheKey(url, maxPixel: maxPixel)
        let nsKey = key as NSURL

        if let cached = memory.object(forKey: nsKey) { return cached }

        // De-dupe concurrent requests for the same URL+size. Keyed by the composite
        // key (URL + maxPixel) because a different size must NOT reuse an in-flight
        // task for a different size of the same URL.
        if let existing = inFlight[key] { return await existing.value }

        let task = Task<PlatformImage?, Never> { [session, diskDir] in
            let diskPath = diskDir.appendingPathComponent(Self.fileName(for: key))

            // 1) Decoded image already on disk? Load it directly.
            if let data = try? Data(contentsOf: diskPath),
               let image = PlatformImage(data: data) {
                return image
            }

            // 2) Fetch raw bytes (URLCache may serve these without the network).
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            guard let (data, _) = try? await session.data(for: request) else { return nil }

            // 3) Downsample at decode time via ImageIO (much cheaper than full decode).
            guard let image = Self.downsample(data: data, maxPixel: maxPixel) else {
                return PlatformImage(data: data)
            }

            // 4) Persist the downsampled JPEG for instant future loads.
            if let jpeg = image.jpegData(compressionQuality: 0.85) {
                try? jpeg.write(to: diskPath, options: .atomic)
            }
            return image
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result {
            let cost = Int(result.size.width * result.size.height * 4)
            memory.setObject(result, forKey: nsKey, cost: cost)
        }
        return result
    }

    private func cacheKey(_ url: URL, maxPixel: CGFloat) -> URL {
        URL(string: url.absoluteString + "#\(Int(maxPixel))") ?? url
    }

    /// Warm the cache for a set of URLs (e.g. the next rows in a grid) so they're
    /// already decoded by the time they scroll on screen. Fire-and-forget.
    nonisolated func prefetch(_ urls: [URL], maxPixel: CGFloat = 600) {
        Task.detached(priority: .utility) {
            for url in urls {
                _ = await self.image(for: url, maxPixel: maxPixel)
            }
        }
    }

    private static func fileName(for key: URL) -> String {
        // Stable, filesystem-safe name from a SHA-256 of the key. Swift's hashValue is
        // randomized per process launch, so it could never reuse a disk file across
        // launches — SHA-256 is deterministic, so cached decodes actually persist.
        let digest = SHA256.hash(data: Data(key.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".jpg"
    }

    // Disk-cache eviction budget for the decoded-image directory.
    private static let maxDiskAge: TimeInterval = 14 * 24 * 3600   // 14 days
    private static let maxDiskBytes: Int = 300 * 1024 * 1024       // 300 MB

    /// Removes decoded images that are too old, then, if still over budget, deletes the
    /// least-recently-used files until under the size cap. Runs off the actor.
    nonisolated static func evictDiskCache(in dir: URL) {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys,
                                                      options: [.skipsHiddenFiles]) else { return }
        let now = Date()
        struct Entry { let url: URL; let date: Date; let size: Int }
        var entries: [Entry] = []
        for u in items {
            let v = try? u.resourceValues(forKeys: Set(keys))
            let date = v?.contentModificationDate ?? .distantPast
            let size = v?.totalFileAllocatedSize ?? v?.fileSize ?? 0
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
            try? fm.removeItem(at: e.url)
            total -= e.size
            if total <= maxDiskBytes { break }
        }
    }

    /// Downsamples image data to `maxPixel` on the long edge using ImageIO, which
    /// decodes directly at the target size rather than allocating the full image.
    private static func downsample(data: Data, maxPixel: CGFloat) -> PlatformImage? {
        let srcOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, srcOptions) else { return nil }
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

/// A drop-in replacement for AsyncImage that uses the shared disk-backed cache.
/// Mirrors the common phase-based API enough for our call sites.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    /// Target long-edge resolution to decode at. Larger surfaces (backdrops, hero
    /// posters) pass a higher value so images stay crisp on Retina displays instead
    /// of being upscaled from a small thumbnail.
    var maxPixel: CGFloat = 600
    @ViewBuilder var content: (Image) -> Content
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var loaded: PlatformImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let loaded {
                content(Image(uiImage: loaded).interpolation(.high).antialiased(true))
                    .transition(.opacity)
            } else {
                placeholder()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: loaded != nil)
        .task(id: url) {
            loaded = nil
            failed = false
            guard let url else { return }
            if let image = await ImageLoader.shared.image(for: url, maxPixel: maxPixel) {
                loaded = image
            } else {
                failed = true
            }
        }
    }
}
