//
//  LibraryEnricher.swift
//  Astra
//

import Foundation

@MainActor
final class LibraryEnricher: ObservableObject {
    @Published var isRunning = false
    @Published var progress: String?
    @Published var fractionComplete: Double = 0
    @Published var lastSummary: String?

    private let session: URLSession = AppNetworking.shared

    struct Options {
        var fetchImages: Bool
        var cleanTitles: Bool
        var useAI: Bool
    }

    func enrichLibrary(using env: AppEnvironment, options: Options) async {
        guard !isRunning else { return }
        isRunning = true
        progress = "Starting…"
        fractionComplete = 0
        defer { isRunning = false; progress = nil; fractionComplete = 0 }

        let items = env.library.items
        var titlesFixed = 0
        var imagesAdded = 0

        for (index, original) in items.enumerated() {
            progress = "Processing \(index + 1) of \(items.count)…"
            fractionComplete = items.isEmpty ? 1 : Double(index + 1) / Double(items.count)
            var item = original
            var changed = false

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

            if options.fetchImages, item.posterURL == nil {
                let query = item.seriesTitle ?? item.title
                if let match = try? await env.tmdb.search(query), let best = match.first {
                    if item.posterURL == nil { item.posterURL = best.posterURL }
                    if item.backdropURL == nil { item.backdropURL = best.backdropURL ?? best.posterURL }
                    if item.contentID == nil { item.contentID = best.contentID }
                    if item.posterURL != nil { imagesAdded += 1; changed = true }
                }
            }

            if changed { env.library.update(item) }
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
