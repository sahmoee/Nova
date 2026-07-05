//
//  ImageCache.swift
//  FrameTV
//
//  A lightweight two-tier image cache so posters and stills load instantly on
//  revisit instead of being re-downloaded every time (plain AsyncImage does no
//  persistent caching). Tier 1 is an in-memory NSCache of decoded UIImages; tier
//  2 is a disk-backed URLCache on a dedicated URLSession.
//

import SwiftUI
import ImageIO

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
        diskDir = caches.appendingPathComponent("frametv-images", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDir, withIntermediateDirectories: true)

        #if os(iOS)
        // Drop the in-memory decoded images when the system is under memory pressure,
        // keeping the (cheap) disk cache. Prevents image growth from causing jetsams.
        Task { @MainActor in
            NotificationCenter.default.addObserver(
                forName: UIApplication.didReceiveMemoryWarningNotification,
                object: nil, queue: .main) { _ in
                Task { await ImageLoader.shared.purgeMemory() }
            }
        }
        #endif
    }

    /// Clears the in-memory image cache. The disk cache is retained.
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

        // De-dupe concurrent requests for the same URL+size.
        if let existing = inFlight[url] { return await existing.value }

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
        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil
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
        // Stable, filesystem-safe name from the URL hash.
        String(UInt(bitPattern: key.absoluteString.hashValue))
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
