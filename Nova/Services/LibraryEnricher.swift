//
//  LibraryEnricher.swift
//  Nova
//

import Foundation

@MainActor
final class LibraryEnricher: ObservableObject {
    @Published var isRunning = false
    @Published var progress: String?
    @Published var fractionComplete: Double = 0
    @Published var lastSummary: String?

    private let session: URLSession = AppNetworking.shared

    struct Options: Sendable {
        var fetchImages: Bool
        var cleanTitles: Bool
        var useAI: Bool
    }

    /// Maximum number of items enriched concurrently. Each item may make one AI
    /// Worker call and one TMDB search, so this bounds in-flight requests.
    private static let maxConcurrentItems = 6

    /// The outcome of enriching one item, applied to the library in one batch.
    private struct ItemResult: Sendable {
        let id: UUID
        var cleanedTitle: String?
        var posterURL: URL?
        var backdropURL: URL?
        var contentID: ContentID?
    }

    func enrichLibrary(using env: AppEnvironment, options: Options) async {
        guard !isRunning else { return }
        isRunning = true
        progress = "Starting…"
        defer { isRunning = false; progress = nil }

        let items = env.library.items
        let tmdb = env.tmdb
        let total = items.count
        fractionComplete = total == 0 ? 1 : 0

        // Bounded-concurrency fan-out (same shape as AISearchService.resolve /
        // ImageCache prefetch): at most `maxConcurrentItems` items in flight.
        let results: [ItemResult] = await withTaskGroup(of: ItemResult?.self) { group in
            var nextIndex = 0
            let initial = min(Self.maxConcurrentItems, total)
            while nextIndex < initial {
                let item = items[nextIndex]
                group.addTask { await self.enrich(item, tmdb: tmdb, options: options) }
                nextIndex += 1
            }
            var collected: [ItemResult] = []
            var completed = 0
            for await result in group {
                completed += 1
                fractionComplete = Double(completed) / Double(total)
                progress = "Processing \(completed) of \(total)…"
                if let result { collected.append(result) }
                if nextIndex < total {
                    let item = items[nextIndex]
                    group.addTask { await self.enrich(item, tmdb: tmdb, options: options) }
                    nextIndex += 1
                }
            }
            return collected
        }

        // Apply the changes onto the *current* library items (the library may
        // have changed while requests were in flight, e.g. playback progress),
        // then persist once via the batch API instead of once per item.
        var titlesFixed = 0
        var imagesAdded = 0
        var updated: [MediaItem] = []
        for result in results {
            guard var item = env.library.item(id: result.id) else { continue }
            var changed = false
            if let title = result.cleanedTitle, title != item.title {
                item.title = title
                titlesFixed += 1
                changed = true
            }
            if item.posterURL == nil, let poster = result.posterURL {
                item.posterURL = poster
                if item.backdropURL == nil { item.backdropURL = result.backdropURL ?? poster }
                if item.contentID == nil { item.contentID = result.contentID }
                imagesAdded += 1
                changed = true
            }
            if changed { updated.append(item) }
        }
        env.library.update(contentsOf: updated)

        lastSummary = summary(titlesFixed: titlesFixed, imagesAdded: imagesAdded, options: options)
    }

    /// Computes the enrichment for a single item without mutating the library.
    /// Returns nil when nothing would change.
    private func enrich(_ item: MediaItem, tmdb: TMDBClient, options: Options) async -> ItemResult? {
        var result = ItemResult(id: item.id)
        var changed = false

        if options.cleanTitles {
            let source = item.metadata.filename ?? item.title
            var cleaned = MetadataParser.cleanTitle(from: source)
            if options.useAI, let aiTitle = await aiCleanTitle(source) {
                cleaned = aiTitle
            }
            if !cleaned.isEmpty, cleaned != item.title {
                result.cleanedTitle = cleaned
                changed = true
            }
        }

        if options.fetchImages, item.posterURL == nil {
            let query = item.seriesTitle ?? result.cleanedTitle ?? item.title
            if let match = try? await tmdb.search(query), let best = match.first, let poster = best.posterURL {
                result.posterURL = poster
                result.backdropURL = best.backdropURL
                result.contentID = best.contentID
                changed = true
            }
        }

        return changed ? result : nil
    }

    private func summary(titlesFixed: Int, imagesAdded: Int, options: Options) -> String {
        var parts: [String] = []
        if options.cleanTitles { parts.append("cleaned \(titlesFixed) title\(titlesFixed == 1 ? "" : "s")") }
        if options.fetchImages { parts.append("added \(imagesAdded) image\(imagesAdded == 1 ? "" : "s")") }
        if parts.isEmpty { return "Nothing to update." }
        return "Done — " + parts.joined(separator: " and ") + "."
    }

    private func aiCleanTitle(_ raw: String) async -> String? {
        guard AISearchService.isConfigured, let base = AISearchService.workerURL else { return nil }
        // Route to the Worker's /titles endpoint like AISearchService and
        // BackupManager do; posting to the bare base URL silently failed.
        let url = NovaWorkerConfiguration.endpoint(base: base, path: NovaIdentifiers.WorkerPath.titles)
        let prompt = "Return only the clean movie or TV show title for this filename, with no year, resolution, codec, or release tags: \(raw)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // FIX: attach the Worker auth headers like every other Worker call does.
        // Without them, a token-protected Worker rejects all AI title cleanups.
        for (k, v) in AISearchService.authHeaders { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try? JSONEncoder().encode(["query": prompt])
        req.timeoutInterval = 20
        guard let (data, response) = try? await session.data(for: req),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        if let decoded = try? JSONDecoder().decode(AIEnrichResponse.self, from: data),
           let first = decoded.titles.first?.trimmingCharacters(in: .whitespacesAndNewlines),
           !first.isEmpty {
            return first
        }
        return nil
    }
}

private struct AIEnrichResponse: Codable {
    let titles: [String]
}
