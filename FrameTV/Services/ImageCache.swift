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

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#endif

actor ImageLoader {
    static let shared = ImageLoader()

    private let session: URLSession
    private let memory = NSCache<NSURL, PlatformImage>()
    private var inFlight: [URL: Task<PlatformImage?, Never>] = [:]

    init() {
        // 50 MB memory + 200 MB disk URLCache dedicated to images.
        let cache = URLCache(memoryCapacity: 50 * 1024 * 1024,
                             diskCapacity: 200 * 1024 * 1024,
                             directory: nil)
        let config = URLSessionConfiguration.default
        config.urlCache = cache
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)
        memory.countLimit = 300
    }

    func image(for url: URL) async -> PlatformImage? {
        if let cached = memory.object(forKey: url as NSURL) { return cached }

        // De-dupe concurrent requests for the same URL.
        if let existing = inFlight[url] { return await existing.value }

        let task = Task<PlatformImage?, Never> { [session] in
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            guard let (data, _) = try? await session.data(for: request),
                  let image = PlatformImage(data: data) else { return nil }
            return image
        }
        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil
        if let result { memory.setObject(result, forKey: url as NSURL) }
        return result
    }
}

/// A drop-in replacement for AsyncImage that uses the shared disk-backed cache.
/// Mirrors the common phase-based API enough for our call sites.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var content: (Image) -> Content
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var loaded: PlatformImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let loaded {
                content(Image(uiImage: loaded))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            loaded = nil
            failed = false
            guard let url else { return }
            if let image = await ImageLoader.shared.image(for: url) {
                loaded = image
            } else {
                failed = true
            }
        }
    }
}
