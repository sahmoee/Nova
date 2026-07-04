//
//  LibraryEnricher.swift
//  FrameTV
//
//  Cleans up library titles and fetches poster/backdrop artwork. Filenames like
//  "WALL-E 2008 1080p" become "WALL-E", and items missing a poster get one from TMDB.
//  An optional AI-assisted mode uses the user's Worker to turn a messy filename into a
//  clean, searchable title before matching against TMDB.
//

import Foundation

@MainActor
final class LibraryEnricher: ObservableObject {
    @Published var isRunning = false
    @Published var progress: String?
    @Published var lastSummary: String?

    private let session: URLSession = AppNetworking.shared

    /// What an enrichment pass should do.
    struct Options {
        var fetchImages: Bool
        var cleanTitles: Bool
        var useAI: Bool
    }

    /// Runs enrichment across the whole library.
    func enrichLibrary(using env: AppEnvironment, options: Options) async {
        guard !isRunning else { return }
        isRunning = true
        progress = "Starting…"
        defer { isRunning = false; progress = nil }

        let items = env.library.items
        var titlesFixed = 0
        var imagesAdded = 0

        for (index, original) in items.enumerated() {
            progress = "Processing \(index + 1) of \(items.count)…"
            var item = original
            var changed = false

            // 1. Clean the display title from the filename/current title.
            if options.cleanTitles {
                let source = item.metadata.filename ?? item.title
                var cleaned = MetadataParser.cleanTitle(from: source)
                if options.useAI, let aiTitle = await aiCleanTitle(source) {
                    cleaned = aiTitle
                }
                if !cleaned.isEmpty, cleaned != item.title {
                    item.title = cleaned
                    changed = true
                    titlesFixed += 1
                }
            }

            // 2. Fetch a poster/backdrop when missing, matching by the (cleaned) title.
            if options.fetchImages, item.posterURL == nil {
                let query = item.seriesTitle ?? item.title
                if let match = try? await env.tmdb.search(query), let best = match.first {
                    if item.posterURL == nil { item.posterURL = best.posterURL; changed = item.posterURL != nil || changed }
                    if item.backdropURL == nil { item.backdropURL = best.backdropURL ?? best.posterURL }
                    if item.contentID == nil { item.contentID = best.contentID }
                    if item.posterURL != nil { imagesAdded += 1 }
                }
            }

            if changed {
                env.library.update(item)
            }
        }

        lastSummary = summary(titlesFixed: titlesFixed, imagesAdded: imagesAdded, options: options)
    }

    private func summary(titlesFixed: Int, imagesAdded: Int, options: Options) -> String {
        var parts: [String] = []
        if options.cleanTitles { parts.append("cleaned \(titlesFixed) title\(titlesFixed == 1 ? "" : "s")") }
        if options.fetchImages { parts.append("added \(imagesAdded) image\(imagesAdded == 1 ? "" : "s")") }
        if parts.isEmpty { return "Nothing to update." }
        return "Done — " + parts.joined(separator: " and ") + "."
    }

    // MARK: - AI-assisted title cleanup

    /// Asks the Worker to turn a messy filename into a clean movie/show title. Falls
    /// back to nil if the Worker isn't configured or returns nothing usable.
    private func aiCleanTitle(_ raw: String) async -> String? {
        guard AISearchService.isConfigured, let url = AISearchService.workerURL else { return nil }
        let prompt = "Return only the clean movie or TV show title for this filename, with no year, resolution, codec, or release tags: \(raw)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(["query": prompt])
        req.timeoutInterval = 20
        guard let (data, response) = try? await session.data(for: req),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        // The Worker returns { "titles": [...] }; use the first suggestion.
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
