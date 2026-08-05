//
//  StremioAddonClient.swift
//  Nova
//
//  Generic client for Stremio-protocol addons. Works with any addon that exposes
//  a manifest and stream/subtitle resources — which includes Stremio community
//  addons, AIOStreams, and Comet. Nova never bundles or recommends addons; the
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

struct AddonProbe: Sendable {
    let manifestLatencyMS: Int
    let resourceLatencyMS: Int?
}

struct AddonStreamProgress: Sendable {
    enum Phase: Sendable, Equatable { case started, succeeded, failed, circuitOpen }
    let addonID: UUID
    let addonName: String
    let phase: Phase
    let streams: [StreamOption]
    let latencyMS: Int?
    let message: String?
}

struct AddonReliabilitySnapshot: Sendable {
    let successRate: Double
    let averageLatencyMS: Int?
    let consecutiveFailures: Int
    let circuitOpenUntil: Date?
}

private actor AddonReliabilityTracker {
    private struct State {
        var successes = 0
        var failures = 0
        var consecutiveFailures = 0
        var totalLatencyMS = 0
        var circuitOpenUntil: Date?
    }
    private var states: [UUID: State] = [:]

    func shouldAllow(_ id: UUID) -> Bool {
        guard let until = states[id]?.circuitOpenUntil else { return true }
        return until <= Date()
    }

    func recordSuccess(_ id: UUID, latencyMS: Int) {
        var state = states[id] ?? State()
        state.successes += 1
        state.consecutiveFailures = 0
        state.totalLatencyMS += latencyMS
        state.circuitOpenUntil = nil
        states[id] = state
    }

    func recordFailure(_ id: UUID) {
        var state = states[id] ?? State()
        state.failures += 1
        state.consecutiveFailures += 1
        if state.consecutiveFailures >= 3 {
            let seconds = min(pow(2.0, Double(state.consecutiveFailures - 3)) * 30, 15 * 60)
            state.circuitOpenUntil = Date().addingTimeInterval(seconds)
        }
        states[id] = state
    }

    func snapshot(_ id: UUID) -> AddonReliabilitySnapshot {
        let state = states[id] ?? State()
        let attempts = state.successes + state.failures
        return AddonReliabilitySnapshot(
            successRate: attempts == 0 ? 1 : Double(state.successes) / Double(attempts),
            averageLatencyMS: state.successes == 0 ? nil : state.totalLatencyMS / state.successes,
            consecutiveFailures: state.consecutiveFailures,
            circuitOpenUntil: state.circuitOpenUntil
        )
    }
}

actor StremioAddonClient {

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let reliability = AddonReliabilityTracker()

    init(session: URLSession = AppNetworking.shared) {
        self.session = session
    }

    // MARK: - Manifest

    /// Fetches and parses an addon manifest, returning an InstalledAddon shell.
    /// Manifest fetch with exponential-backoff retry, for background contexts
    /// (update checks, health probes) where transient failures shouldn't count
    /// against the addon. Install flows keep the fast-fail fetchManifest below.
    func fetchManifestRetrying(at manifestURL: URL) async throws -> InstalledAddon {
        try await withRetry(maxAttempts: 3, initialDelay: 1.0) {
            try await self.fetchManifest(at: manifestURL)
        }
    }

    func fetchManifest(at manifestURL: URL) async throws -> InstalledAddon {
        // Short timeout, no retry, so a bad/unreachable URL fails quickly instead of
        // leaving the install button spinning for the full retry window.
        let req: URLRequest = {
            var r = URLRequest(url: manifestURL)
            r.timeoutInterval = 10
            r.setValue("application/json", forHTTPHeaderField: "Accept")
            return r
        }()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw AddonError.network(error)
        }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AddonError.manifestFetchFailed
        }
        let manifest: AddonManifest
        do {
            manifest = try decoder.decode(AddonManifest.self, from: data)
        } catch {
            throw AddonError.decoding(error)
        }
        let catalogs = (manifest.catalogs ?? []).map {
            AddonCatalogRef(type: $0.type, catalogID: $0.id,
                            name: $0.name ?? "\($0.type.capitalized)")
        }
        return InstalledAddon(
            manifestURL: manifestURL,
            name: manifest.name,
            version: manifest.version,
            description: manifest.description,
            resources: manifest.resourceNames,
            types: manifest.types ?? [],
            catalogs: catalogs
        )
    }

    /// Exercises the manifest plus one real advertised resource, so a health check
    /// catches add-ons that are configured but whose backing service is broken.
    func probe(addon: InstalledAddon) async throws -> AddonProbe {
        let manifestStart = Date()
        _ = try await fetchManifest(at: addon.manifestURL)
        let manifestMS = Int(Date().timeIntervalSince(manifestStart) * 1_000)
        let resourceStart = Date()
        if let catalog = addon.catalogs.first, addon.supports(resource: "catalog") {
            _ = try await self.catalog(from: addon, type: catalog.type,
                                       catalogID: catalog.catalogID, skip: 0)
        } else if addon.supports(resource: "stream") {
            _ = try await streams(from: addon, type: .movie, stremioID: "tt0111161")
        } else if addon.supports(resource: "subtitles") {
            _ = try await subtitles(from: addon, type: .movie, stremioID: "tt0111161")
        } else {
            return AddonProbe(manifestLatencyMS: manifestMS, resourceLatencyMS: nil)
        }
        return AddonProbe(manifestLatencyMS: manifestMS,
                          resourceLatencyMS: Int(Date().timeIntervalSince(resourceStart) * 1_000))
    }

    func reliabilitySnapshot(for addonID: UUID) async -> AddonReliabilitySnapshot {
        await reliability.snapshot(addonID)
    }

    // MARK: - Catalogs (home shelves + live TV channel lists)

    /// Fetches the metas for a catalog and maps them to CatalogItems.
    /// Optional `search` and `genre` become query params per the Stremio protocol.
    func catalog(from addon: InstalledAddon,
                 type: String,
                 catalogID: String,
                 search: String? = nil,
                 genre: String? = nil,
                 skip: Int = 0) async throws -> [CatalogItem] {
        guard addon.supports(resource: "catalog") else { return [] }

        var url = addon.baseURL
            .appendingPathComponent("catalog")
            .appendingPathComponent(type)

        // Extra path segments for search/genre (Stremio uses "/search=foo.json").
        var extras: [String] = []
        if let search, !search.isEmpty {
            let enc = search.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? search
            extras.append("search=\(enc)")
        }
        if let genre, !genre.isEmpty {
            let enc = genre.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? genre
            extras.append("genre=\(enc)")
        }
        // Stremio pagination: "/skip=100.json" asks for the next page.
        if skip > 0 {
            extras.append("skip=\(skip)")
        }
        if extras.isEmpty {
            url.appendPathComponent("\(catalogID).json")
        } else {
            url.appendPathComponent(catalogID)
            url.appendPathComponent(extras.joined(separator: "&") + ".json")
        }

        guard await reliability.shouldAllow(addon.id) else { return [] }
        let start = Date()
        do {
            let response: AddonCatalogResponse = try await getJSON(url, wrap: AddonError.manifestFetchFailed)
            await reliability.recordSuccess(addon.id, latencyMS: Int(Date().timeIntervalSince(start) * 1_000))
            let metas = response.metas ?? []
            return metas.compactMap { $0.toCatalogItem(defaultType: type) }
        } catch {
            await reliability.recordFailure(addon.id)
            throw error
        }
    }

    /// Resolves the playable stream(s) for a live channel meta id.
    func channelStreams(from addon: InstalledAddon, channelID: String) async throws -> [StreamOption] {
        try await streams(from: addon, type: .tv, stremioID: channelID)
    }

    // MARK: - Streams

    /// Queries one addon for streams for the given content id.
    /// `stremioID` is the fully-formed id (e.g. "tt0903747" or "tt0903747:1:2").
    func streams(from addon: InstalledAddon,
                 type: ContentType,
                 stremioID: String) async throws -> [StreamOption] {
        guard addon.supports(resource: "stream") else { return [] }

        let typePath = type.stremioPath
        let url = addon.baseURL
            .appendingPathComponent("stream")
            .appendingPathComponent(typePath)
            .appendingPathComponent("\(stremioID).json")

        guard await reliability.shouldAllow(addon.id) else { return [] }
        let start = Date()
        do {
            let response: AddonStreamResponse = try await getJSON(url, wrap: AddonError.manifestFetchFailed)
            await reliability.recordSuccess(addon.id, latencyMS: Int(Date().timeIntervalSince(start) * 1_000))
            let raw = response.streams ?? []
            return raw.map { StreamRanker.normalize($0, addonName: addon.name) }
        } catch {
            await reliability.recordFailure(addon.id)
            throw error
        }
    }

    // MARK: - Subtitles

    func subtitles(from addon: InstalledAddon,
                   type: ContentType,
                   stremioID: String) async throws -> [SubtitleTrack] {
        guard addon.supports(resource: "subtitles") else { return [] }

        let typePath = type.stremioPath
        let url = addon.baseURL
            .appendingPathComponent("subtitles")
            .appendingPathComponent(typePath)
            .appendingPathComponent("\(stremioID).json")

        guard await reliability.shouldAllow(addon.id) else { return [] }
        let start = Date()
        do {
            let response: AddonSubtitleResponse = try await getJSON(url, wrap: AddonError.manifestFetchFailed)
            await reliability.recordSuccess(addon.id, latencyMS: Int(Date().timeIntervalSince(start) * 1_000))
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
        } catch {
            await reliability.recordFailure(addon.id)
            throw error
        }
    }

    // MARK: - Fan-out helpers (query several addons at once)

    /// Soft per-addon deadline for fan-out queries: one slow addon shouldn't stall
    /// the merged results the picker is waiting on.
    private static let fanOutTimeout: Duration = .seconds(12)

    /// Runs an operation with a deadline; returns the fallback if time runs out.
    private static func withTimeout<T: Sendable>(_ limit: Duration,
                                                 fallback: T,
                                                 _ operation: @escaping @Sendable () async -> T) async -> T {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(for: limit)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? fallback
        }
    }

    /// Queries all enabled stream-capable addons concurrently and merges results.
    func allStreams(from addons: [InstalledAddon],
                    type: ContentType,
                    stremioID: String) async -> [StreamOption] {
        let streamAddons = addons.filter { $0.isEnabled && $0.supports(resource: "stream") }
        guard !streamAddons.isEmpty else { return [] }

        let merged: [StreamOption] = await withTaskGroup(of: [StreamOption].self) { group in
            for addon in streamAddons {
                group.addTask {
                    await Self.withTimeout(Self.fanOutTimeout, fallback: []) {
                        (try? await self.streams(from: addon, type: type, stremioID: stremioID)) ?? []
                    }
                }
            }
            var out: [StreamOption] = []
            for await chunk in group { out.append(contentsOf: chunk) }
            return out
        }
        // Several addons often return the exact same torrent; collapse duplicates.
        return StreamRanker.dedupeByIdentity(merged)
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
                            await Self.withTimeout(Self.fanOutTimeout, fallback: []) {
                                (try? await self.streams(from: addon, type: type, stremioID: stremioID)) ?? []
                            }
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

    /// Rich progressive fan-out used by the picker to show per-add-on progress,
    /// result count, latency, failures, and circuit-breaker state.
    nonisolated func streamProgress(from addons: [InstalledAddon],
                                    type: ContentType,
                                    stremioID: String) -> AsyncStream<AddonStreamProgress> {
        let streamAddons = addons.filter { $0.isEnabled && $0.supports(resource: "stream") }
        return AsyncStream { continuation in
            guard !streamAddons.isEmpty else { continuation.finish(); return }
            for addon in streamAddons {
                continuation.yield(.init(addonID: addon.id, addonName: addon.name,
                                         phase: .started, streams: [], latencyMS: nil, message: nil))
            }
            let task = Task {
                await withTaskGroup(of: AddonStreamProgress.self) { group in
                    for addon in streamAddons {
                        group.addTask {
                            let allowed = await self.reliability.shouldAllow(addon.id)
                            guard allowed else {
                                return .init(addonID: addon.id, addonName: addon.name,
                                             phase: .circuitOpen, streams: [], latencyMS: nil,
                                             message: "Paused after repeated failures")
                            }
                            let start = Date()
                            do {
                                let streams = try await Self.withThrowingTimeout(Self.fanOutTimeout) {
                                    try await self.streams(from: addon, type: type, stremioID: stremioID)
                                }
                                return .init(addonID: addon.id, addonName: addon.name,
                                             phase: .succeeded, streams: streams,
                                             latencyMS: Int(Date().timeIntervalSince(start) * 1_000), message: nil)
                            } catch {
                                return .init(addonID: addon.id, addonName: addon.name,
                                             phase: .failed, streams: [],
                                             latencyMS: Int(Date().timeIntervalSince(start) * 1_000),
                                             message: error.localizedDescription)
                            }
                        }
                    }
                    for await progress in group { continuation.yield(progress) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func withThrowingTimeout<T: Sendable>(
        _ limit: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: limit)
                throw CancellationError()
            }
            guard let first = try await group.next() else { throw CancellationError() }
            group.cancelAll()
            return first
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
                    await Self.withTimeout(Self.fanOutTimeout, fallback: []) {
                        (try? await self.subtitles(from: addon, type: type, stremioID: stremioID)) ?? []
                    }
                }
            }
            var merged: [SubtitleTrack] = []
            for await chunk in group { merged.append(contentsOf: chunk) }
            return merged
        }
    }

    // MARK: - Networking

    private func getJSON<T: Decodable>(_ url: URL, wrap fetchError: AddonError,
                                       attempts: Int = 2) async throws -> T {
        // Build the request immutably so it can be safely captured by the retry
        // closure (a mutable var capture is an error in the Swift 6 language mode).
        let req: URLRequest = {
            var r = URLRequest(url: url)
            r.timeoutInterval = 25
            r.setValue("application/json", forHTTPHeaderField: "Accept")
            return r
        }()

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await withRetry(maxAttempts: attempts) {
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
