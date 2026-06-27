//
//  StremioAddonClient.swift
//  FrameTV
//
//  Generic client for Stremio-protocol addons. Works with any addon that exposes
//  a manifest and stream/subtitle resources — which includes Stremio community
//  addons, AIOStreams, and Comet. FrameTV never bundles or recommends addons; the
//  user installs their own by manifest URL.
//
//  Request shapes (Stremio protocol):
//    Manifest:   GET <base>/manifest.json
//    Streams:    GET <base>/stream/<type>/<id>.json
//    Subtitles:  GET <base>/subtitles/<type>/<id>.json
//  where <id> is an IMDB id for movies (tt123...) and imdb:season:episode for
//  series episodes (e.g. tt123:1:2).
//

import Foundation

enum AddonError: LocalizedError {
    case invalidManifestURL
    case manifestFetchFailed
    case notAStreamAddon
    case network(Error)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidManifestURL:  return "That doesn't look like a valid addon manifest URL."
        case .manifestFetchFailed: return "Couldn't load the addon manifest. Check the URL."
        case .notAStreamAddon:     return "That addon doesn't provide streams."
        case .network(let e):      return "Network error contacting the addon: \(e.localizedDescription)"
        case .decoding:            return "Couldn't read the addon's response."
        }
    }
}

actor StremioAddonClient {

    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Manifest

    /// Fetches and parses an addon manifest, returning an InstalledAddon shell.
    func fetchManifest(at manifestURL: URL) async throws -> InstalledAddon {
        let manifest: AddonManifest = try await getJSON(manifestURL, wrap: AddonError.manifestFetchFailed)
        return InstalledAddon(
            manifestURL: manifestURL,
            name: manifest.name,
            version: manifest.version,
            description: manifest.description,
            resources: manifest.resourceNames,
            types: manifest.types ?? []
        )
    }

    // MARK: - Streams

    /// Queries one addon for streams for the given content id.
    /// `stremioID` is the fully-formed id (e.g. "tt0903747" or "tt0903747:1:2").
    func streams(from addon: InstalledAddon,
                 type: ContentType,
                 stremioID: String) async throws -> [StreamOption] {
        guard addon.supports(resource: "stream") else { return [] }

        let typePath = (type == .movie) ? "movie" : "series"
        let url = addon.baseURL
            .appendingPathComponent("stream")
            .appendingPathComponent(typePath)
            .appendingPathComponent("\(stremioID).json")

        let response: AddonStreamResponse = try await getJSON(url, wrap: AddonError.manifestFetchFailed)
        let raw = response.streams ?? []
        return raw.map { StreamRanker.normalize($0, addonName: addon.name) }
    }

    // MARK: - Subtitles

    func subtitles(from addon: InstalledAddon,
                   type: ContentType,
                   stremioID: String) async throws -> [SubtitleTrack] {
        guard addon.supports(resource: "subtitles") else { return [] }

        let typePath = (type == .movie) ? "movie" : "series"
        let url = addon.baseURL
            .appendingPathComponent("subtitles")
            .appendingPathComponent(typePath)
            .appendingPathComponent("\(stremioID).json")

        let response: AddonSubtitleResponse = try await getJSON(url, wrap: AddonError.manifestFetchFailed)
        let raw = response.subtitles ?? []
        return raw.compactMap { sub in
            guard let urlString = sub.url, let url = URL(string: urlString) else { return nil }
            let lang = sub.lang ?? "und"
            return SubtitleTrack(
                id: sub.id ?? UUID().uuidString,
                language: lang,
                languageDisplay: LanguageNames.display(for: lang),
                url: url,
                isEmbedded: false,
                source: addon.name
            )
        }
    }

    // MARK: - Fan-out helpers (query several addons at once)

    /// Queries all enabled stream-capable addons concurrently and merges results.
    func allStreams(from addons: [InstalledAddon],
                    type: ContentType,
                    stremioID: String) async -> [StreamOption] {
        let streamAddons = addons.filter { $0.isEnabled && $0.supports(resource: "stream") }
        guard !streamAddons.isEmpty else { return [] }

        return await withTaskGroup(of: [StreamOption].self) { group in
            for addon in streamAddons {
                group.addTask {
                    (try? await self.streams(from: addon, type: type, stremioID: stremioID)) ?? []
                }
            }
            var merged: [StreamOption] = []
            for await chunk in group { merged.append(contentsOf: chunk) }
            return merged
        }
    }

    /// Returns an async stream that yields each stream-capable addon's results as
    /// they arrive, so the consumer (on its own actor) can update the UI
    /// progressively without a cross-actor callback.
    nonisolated func streamsByAddon(from addons: [InstalledAddon],
                                    type: ContentType,
                                    stremioID: String) -> AsyncStream<[StreamOption]> {
        let streamAddons = addons.filter { $0.isEnabled && $0.supports(resource: "stream") }
        return AsyncStream { continuation in
            guard !streamAddons.isEmpty else { continuation.finish(); return }
            let task = Task {
                await withTaskGroup(of: [StreamOption].self) { group in
                    for addon in streamAddons {
                        group.addTask {
                            (try? await self.streams(from: addon, type: type, stremioID: stremioID)) ?? []
                        }
                    }
                    for await chunk in group where !chunk.isEmpty {
                        continuation.yield(chunk)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func allSubtitles(from addons: [InstalledAddon],
                      type: ContentType,
                      stremioID: String) async -> [SubtitleTrack] {
        let subAddons = addons.filter { $0.isEnabled && $0.supports(resource: "subtitles") }
        guard !subAddons.isEmpty else { return [] }

        return await withTaskGroup(of: [SubtitleTrack].self) { group in
            for addon in subAddons {
                group.addTask {
                    (try? await self.subtitles(from: addon, type: type, stremioID: stremioID)) ?? []
                }
            }
            var merged: [SubtitleTrack] = []
            for await chunk in group { merged.append(contentsOf: chunk) }
            return merged
        }
    }

    // MARK: - Networking

    private func getJSON<T: Decodable>(_ url: URL, wrap fetchError: AddonError) async throws -> T {
        var req = URLRequest(url: url)
        req.timeoutInterval = 25
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await withRetry(maxAttempts: 2) {
                try await self.session.data(for: req)
            }
        } catch {
            throw AddonError.network(error)
        }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw fetchError
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw AddonError.decoding(error)
        }
    }
}
