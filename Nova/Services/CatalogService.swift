//
//  CatalogService.swift
//  Nova
//
//  High-level orchestration that the UI talks to. It combines TMDB metadata,
//  addon streams, subtitles, and Real-Debrid resolution into the pieces the
//  player and detail screens need:
//
//    - search(...)                  -> CatalogItems (movies + series)
//    - hydrate(...)                 -> fills seasons/episodes + IMDB id
//    - streams(for:)                -> ranked StreamOptions for a movie/episode
//    - subtitles(for:)              -> merged subtitle tracks
//    - makePlayable(...)            -> resolves a chosen stream into a MediaItem
//
//  Everything degrades gracefully: no TMDB key still allows addon-only flows via
//  Cinemeta; no addons still allows browsing metadata.
//

import Foundation

@MainActor
final class CatalogService: ObservableObject {

    private let tmdb: TMDBClient
    private let addonClient: StremioAddonClient
    private let addonStore: AddonStore
    private let resolver: StreamResolver
    private let openSubtitles: OpenSubtitlesClient
    private let skipProvider: SkipSegmentProvider
    private let hasDebridToken: () -> Bool
    private let searchCache = TTLCache<String, [CatalogItem]>(ttl: 60 * 5, maxEntries: 80)

    init(tmdb: TMDBClient,
         addonClient: StremioAddonClient,
         addonStore: AddonStore,
         resolver: StreamResolver,
         openSubtitles: OpenSubtitlesClient,
         skipProvider: SkipSegmentProvider,
         hasDebridToken: @escaping () -> Bool) {
        self.tmdb = tmdb
        self.addonClient = addonClient
        self.addonStore = addonStore
        self.resolver = resolver
        self.openSubtitles = openSubtitles
        self.skipProvider = skipProvider
        self.hasDebridToken = hasDebridToken
    }

    // MARK: - Search

    func search(_ query: String) async -> [CatalogItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if tmdb.hasKey {
            let key = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            if let cached = await searchCache.value(for: key) { return cached }
            let client = tmdb
            let found = await searchCache.coalesced(for: key) {
                (try? await client.search(trimmed)) ?? []
            }
            if !found.isEmpty { await searchCache.set(found, for: key) }
            return found
        }
        // Without a TMDB key we can't search by text reliably; return empty so the
        // UI can prompt to add a key. (Addons key on ids, not free text.)
        return []
    }

    // MARK: - Hydrate

    /// Fills in seasons/episodes (series) and ensures an IMDB id exists so addon
    /// stream lookups work. Results are cached for the session (with a TTL) so
    /// reopening the same title is instant.
    func hydrate(_ item: CatalogItem) async -> CatalogItem {
        let key = item.contentID.stableKey
        if let cached = await CatalogCaches.metadata.value(for: key),
           // Only trust the cache if it actually has the data we need.
           (!item.isSeries || !cached.seasons.isEmpty) {
            return cached
        }

        let hydrated: CatalogItem
        if item.isSeries {
            hydrated = (try? await tmdb.hydrateSeries(item)) ?? item
        } else {
            hydrated = (try? await tmdb.hydrateMovie(item)) ?? item
        }
        // Cache only meaningful results.
        if hydrated.contentID.imdb != nil || !hydrated.seasons.isEmpty {
            await CatalogCaches.metadata.set(hydrated, for: key)
            // Persist so the title's details/episodes are available offline next time.
            await OfflineMetadataCache.shared.store(hydrated, for: key)
            return hydrated
        }
        // Hydration produced nothing useful (likely offline) — try the disk cache so
        // an already-seen title still shows its episodes/description.
        if item.isSeries, item.seasons.isEmpty,
           let offline = await OfflineMetadataCache.shared.item(for: key) {
            return offline
        }
        return hydrated
    }

    /// Streams series hydration snapshots. The first regular season is fetched
    /// first, then remaining seasons arrive with bounded concurrency.
    func hydrateProgressively(_ item: CatalogItem) -> AsyncStream<CatalogItem> {
        AsyncStream { continuation in
            let task = Task { @MainActor [weak self] in
                guard let self else { continuation.finish(); return }
                let key = item.contentID.stableKey
                if let cached = await CatalogCaches.metadata.value(for: key), !cached.seasons.isEmpty {
                    continuation.yield(cached)
                    continuation.finish()
                    return
                }
                do {
                    let final = try await tmdb.hydrateSeries(item) { partial in
                        continuation.yield(partial)
                    }
                    if !final.seasons.isEmpty || final.contentID.imdb != nil {
                        await CatalogCaches.metadata.set(final, for: key)
                        await OfflineMetadataCache.shared.store(final, for: key)
                    }
                    continuation.yield(final)
                } catch {
                    if let offline = await OfflineMetadataCache.shared.item(for: key) {
                        continuation.yield(offline)
                    } else {
                        continuation.yield(item)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Streams

    /// Builds the Stremio id for a movie or a specific episode.
    func stremioID(for content: ContentID, episode: EpisodeRef?) -> String? {
        guard let imdb = content.imdb else { return nil }
        if content.type == .series, let ep = episode {
            return "\(imdb):\(ep.season):\(ep.number)"
        }
        return imdb
    }

    /// Fetches and ranks streams for a movie or an episode. Cached briefly so
    /// repeat opens of the same item don't re-run the addon fan-out.
    func streams(for content: ContentID,
                 episode: EpisodeRef?,
                 preferredQuality: StreamQuality?) async -> [StreamOption] {
        guard let id = stremioID(for: content, episode: episode) else { return [] }

        if let cached = await CatalogCaches.streams.value(for: id) {
            return StreamRanker.rank(cached, preferredQuality: preferredQuality)
        }

        let addons = addonStore.streamAddons
        let raw = await addonClient.allStreams(from: addons, type: content.type, stremioID: id)
        if !raw.isEmpty {
            await CatalogCaches.streams.set(raw, for: id)
        }
        return StreamRanker.rank(raw, preferredQuality: preferredQuality)
    }

    /// Streams for an item, delivered progressively as each addon responds via the
    /// provided callback. Returns the final merged+ranked list. Lets the UI show
    /// fast addons immediately instead of waiting for the slowest.
    func streamsProgressive(for content: ContentID,
                            episode: EpisodeRef?,
                            preferredQuality: StreamQuality?,
                            onPartial: @escaping ([StreamOption]) -> Void,
                            onStatus: ((AddonStreamProgress) -> Void)? = nil) async -> [StreamOption] {
        guard let id = stremioID(for: content, episode: episode) else { return [] }

        if let cached = await CatalogCaches.streams.value(for: id) {
            let ranked = StreamRanker.rank(cached, preferredQuality: preferredQuality)
            onPartial(ranked)
            return ranked
        }

        let addons = addonStore.streamAddons
        var merged: [StreamOption] = []
        // The stream is consumed here on CatalogService's (main) actor, so it is
        // safe for onPartial to drive UI state.
        for await progress in addonClient.streamProgress(from: addons, type: content.type, stremioID: id) {
            onStatus?(progress)
            merged.append(contentsOf: progress.streams)
            let ranked = StreamRanker.rank(merged, preferredQuality: preferredQuality)
            onPartial(ranked)
        }
        if !merged.isEmpty {
            await CatalogCaches.streams.set(merged, for: id)
        }
        return StreamRanker.rank(merged, preferredQuality: preferredQuality)
    }

    // MARK: - Subtitles

    func subtitles(for content: ContentID, episode: EpisodeRef?) async -> [SubtitleTrack] {
        var tracks: [SubtitleTrack] = []

        if let id = stremioID(for: content, episode: episode) {
            let addonSubs = await addonClient.allSubtitles(
                from: addonStore.subtitleAddons, type: content.type, stremioID: id
            )
            tracks.append(contentsOf: addonSubs)
        }

        if await openSubtitles.hasKey, let imdb = content.imdb {
            // Request several common languages so more subtitle options surface. The
            // player lets the viewer pick; their preferred language is applied there.
            let langs = ["en", "es", "fr", "de", "pt", "it"]
            if let osSubs = try? await openSubtitles.search(
                imdbID: imdb, episode: episode, languages: langs
            ) {
                tracks.append(contentsOf: osSubs)
            }
        }

        return dedupeSubtitles(tracks)
    }

    private func dedupeSubtitles(_ tracks: [SubtitleTrack]) -> [SubtitleTrack] {
        var seen = Set<String>()
        var out: [SubtitleTrack] = []
        for t in tracks {
            let key = "\(t.language)|\(t.url?.absoluteString ?? t.id)"
            if seen.insert(key).inserted { out.append(t) }
        }
        return out
    }

    // MARK: - Make playable

    /// Resolves a chosen stream into a fully-formed MediaItem ready for the player,
    /// attaching metadata, subtitles, and skip segments.
    /// Sends a lightweight HEAD (falling back to a tiny ranged GET) to confirm the
    /// resolved link is live and is real media, not an expired-link error slate.
    /// Throws StreamResolveError.expiredLink when the link is dead so callers can
    /// fail over to another stream. Only checks http(s) URLs; local and SMB URLs pass
    /// through untouched.
    private func validatePlaybackURL(_ url: URL) async throws {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }

        var request = URLRequest(url: url, timeoutInterval: 2)
        request.httpMethod = "GET"
        request.setValue("bytes=0-1", forHTTPHeaderField: "Range")

        do {
            let (_, response) = try await AppNetworking.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }

            // Dead/expired links usually answer 401/403/404/410 or a 5xx.
            if [401, 403, 404, 410].contains(http.statusCode) || http.statusCode >= 500 {
                throw StreamResolveError.expiredLink
            }

            // The ElfHosted-style "Link expired" slate is a very small MP4 served as
            // video. If the server reports a content length and it is implausibly
            // small for real media, treat it as an expired link too.
            let type = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            let rangeLen = http.value(forHTTPHeaderField: "Content-Range")?
                .split(separator: "/").last.map(String.init)
            let lenStr = rangeLen ?? http.value(forHTTPHeaderField: "Content-Length")
            if let lenStr,
               let total = Int64(lenStr.trimmingCharacters(in: .whitespaces)),
               total > 0, total < 3_000_000,          // under ~3 MB
               (type.contains("video") || type.contains("mp4") || type.contains("octet-stream")) {
                throw StreamResolveError.expiredLink
            }
        } catch let error as StreamResolveError {
            throw error
        } catch {
            // Network hiccup on the probe alone shouldn't block playback; let the
            // player attempt it and surface any real failure through recovery.
            return
        }
    }

    func makePlayable(stream: StreamOption,
                      catalog: CatalogItem,
                      episode: EpisodeInfo?) async throws -> MediaItem {
        let url = try await resolver.resolve(stream, hasDebridToken: hasDebridToken())

        // Validate the resolved link before handing it to the player. Expired debrid
        // and addon links commonly return an error status or a tiny error-slate video
        // (e.g. the ElfHosted "Link expired" clip). Catching that here lets the picker
        // auto-fail-over to the next stream instead of playing the error video.
        try await validatePlaybackURL(url)

        let epRef: EpisodeRef? = episode.map {
            EpisodeRef(season: $0.season, number: $0.number, episodeTitle: $0.title)
        }

        let title: String
        if let episode {
            title = episode.displayTitle
        } else {
            title = catalog.title
        }

        let item = MediaItem(
            title: title,
            sourceType: .addon,
            playbackURL: url,
            // Use the show's poster/backdrop art for episodes. Episode stills are cropped
            // 16:9 frames that look wrong as posters, so they're intentionally not used
            // here; a missing poster shows a clean placeholder instead.
            posterURL: catalog.posterURL,
            backdropURL: catalog.backdropURL ?? catalog.posterURL,
            duration: episode?.runtime,
            legalAccessConfirmed: true,
            metadata: MediaMetadata(
                filename: stream.behaviorHints?.filename,
                fileSize: stream.sizeBytes,
                resolution: stream.quality == .unknown ? nil : stream.quality.rawValue,
                season: episode?.season,
                episode: episode?.number,
                year: catalog.year
            ),
            contentID: catalog.contentID,
            episode: epRef,
            seriesTitle: catalog.isSeries ? catalog.title : nil
        )

        // Provider subtitles and skip markers are loaded by PlayerModel after the
        // media becomes ready, keeping them entirely off the playback-start path.
        return item
    }

    func skipSegments(for item: MediaItem) async -> [SkipSegment] {
        await skipProvider.segments(for: item, duration: item.duration)
    }

    // MARK: - Live TV

    /// Loads channels for a live-TV addon catalog.
    func liveChannels(addon: InstalledAddon, catalog: AddonCatalogRef) async -> [CatalogItem] {
        (try? await addonClient.catalog(from: addon, type: catalog.type,
                                        catalogID: catalog.catalogID)) ?? []
    }

    /// Resolves a live channel into a playable MediaItem. Live streams are usually a
    /// direct HLS URL the addon returns, so we take the first resolvable stream.
    func makeLiveChannelPlayable(channel: CatalogItem) async throws -> MediaItem {
        guard let channelID = channel.contentID.stremioBaseID else {
            throw StreamResolveError.noPlayableURL
        }
        // Gather streams across enabled addons that serve tv.
        var found: [StreamOption] = []
        for addon in addonStore.streamAddons where addon.supports(resource: "stream") {
            if let s = try? await addonClient.channelStreams(from: addon, channelID: channelID) {
                found.append(contentsOf: s)
            }
        }
        guard !found.isEmpty else { throw StreamResolveError.noPlayableURL }

        // Prefer a directly-playable URL; resolve through the resolver otherwise.
        let best = found.first(where: { $0.url != nil }) ?? found[0]
        let url = try await resolver.resolve(best, hasDebridToken: hasDebridToken())

        return MediaItem(
            title: channel.title,
            sourceType: .liveTV,
            playbackURL: url,
            posterURL: channel.posterURL,
            backdropURL: channel.backdropURL,
            legalAccessConfirmed: true,
            metadata: MediaMetadata(),
            contentID: channel.contentID
        )
    }

    // MARK: - Next episode

    /// Given the current episode within a hydrated series, returns the next one.
    func nextEpisode(after current: EpisodeRef, in series: CatalogItem) -> EpisodeInfo? {
        let all = series.allEpisodes
        guard let idx = all.firstIndex(where: {
            $0.season == current.season && $0.number == current.number
        }) else { return nil }
        let nextIdx = idx + 1
        return nextIdx < all.count ? all[nextIdx] : nil
    }
}
