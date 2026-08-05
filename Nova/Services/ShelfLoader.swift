//
//  ShelfLoader.swift
//  Nova
//
//  Loads the items for a given home/discover shelf from the right source (Trakt,
//  TMDB, or an addon catalog). Results are cached briefly so switching tabs doesn't
//  refetch constantly.
//

import Foundation

@MainActor
final class ShelfLoader {
    private let tmdb: TMDBClient
    private let trakt: TraktClient
    private let addonClient: StremioAddonClient
    private let addonStore: AddonStore
    /// Resolves an AI shelf prompt into catalog items. Set by AppEnvironment after
    /// the AI service is constructed (avoids an init ordering dependency).
    var aiResolver: ((String) async -> [CatalogItem])?

    // Short-lived cache so Home and Discover share results within a session.
    private let cache = TTLCache<String, [CatalogItem]>(ttl: 60 * 10)   // 10 min

    init(tmdb: TMDBClient, trakt: TraktClient,
         addonClient: StremioAddonClient, addonStore: AddonStore) {
        self.tmdb = tmdb
        self.trakt = trakt
        self.addonClient = addonClient
        self.addonStore = addonStore
    }

    /// Drops the in-memory shelf cache so the next load hits the network (used by
    /// pull-to-refresh). The offline disk cache is kept as a fallback.
    func clearCache() async {
        await cache.removeAll()
    }

    func items(for shelf: ShelfConfig) async -> [CatalogItem] {
        await items(for: shelf, variant: .home)
    }

    /// Variants let Home and Discover present the same source differently. Home shows
    /// the canonical ordering; Discover returns a freshly shuffled selection on every
    /// request so it always looks different and refreshes each time it's shown.
    enum Variant { case home, discover }

    func items(for shelf: ShelfConfig, variant: Variant) async -> [CatalogItem] {
        let key = cacheKey(for: shelf.kind)
        let pool: [CatalogItem]
        if let cached = await cache.value(for: key) {
            pool = cached
        } else {
            // Signposted so shelf load latency is visible in Instruments per shelf.
            let kind = shelf.kind
            let result = await cache.coalesced(for: key) { [weak self] in
                guard let self else { return [] }
                return await Signposts.measure(Signposts.shelf, "shelf.load") {
                    await self.load(kind)
                }
            }
            if !result.isEmpty {
                await cache.set(result, for: key)
                // Persist to disk so this shelf survives a restart and shows offline.
                await OfflineCatalogCache.shared.store(result, for: key)
                pool = result
            } else if let offline = await OfflineCatalogCache.shared.items(for: key) {
                // Network/source returned nothing (slow or offline) — fall back to the
                // last-known contents from disk so the screen isn't empty.
                pool = offline
            } else {
                pool = result
            }
        }

        switch variant {
        case .home:
            return pool
        case .discover:
            // Shuffle so Discover differs from Home, and bias toward items further
            // down the list (which Home shows last) so the overlap is minimized.
            guard pool.count > 4 else { return pool.shuffled() }
            let tail = Array(pool.suffix(from: pool.count / 3))
            return (tail + pool.prefix(pool.count / 3)).shuffled()
        }
    }

    /// Last-known content for stale-while-revalidate rendering. This never starts a
    /// network request and is therefore safe to use for the first paint.
    func cachedItems(for shelf: ShelfConfig, variant: Variant) async -> [CatalogItem] {
        let key = cacheKey(for: shelf.kind)
        let pool: [CatalogItem]
        if let memory = await cache.staleValue(for: key) {
            pool = memory
        } else if let disk = await OfflineCatalogCache.shared.items(for: key) {
            pool = disk
        } else {
            pool = []
        }
        switch variant {
        case .home: return pool
        case .discover: return pool.shuffled()
        }
    }

    /// Cache identity now lives on ShelfKind itself (single source of truth shared
    /// with anything else that needs a stable per-shelf key).
    private func cacheKey(for kind: ShelfKind) -> String { kind.cacheKey }

    private func load(_ kind: ShelfKind) async -> [CatalogItem] {
        switch kind {
        case .traktWatchlist:
            // Trakt returns ids/titles but no images, so fill artwork from TMDB.
            let items = (try? await trakt.watchlist()) ?? []
            return await tmdb.enrichArtwork(items)
        case .traktTrendingShows:
            let items = (try? await trakt.trendingShows()) ?? []
            return await tmdb.enrichArtwork(items)
        case .tmdbTrending:       return (try? await tmdb.trendingMovies()) ?? []
        case .tmdbTrendingShows:  return (try? await tmdb.trendingShows()) ?? []
        case .tmdbPopularMovies:  return (try? await tmdb.popularMovies()) ?? []
        case .tmdbNowPlaying:     return (try? await tmdb.nowPlayingMovies()) ?? []
        case .tmdbTopRated:       return (try? await tmdb.topRatedMovies()) ?? []
        case .tmdbPopularShows:   return (try? await tmdb.popularShows()) ?? []
        case .tmdbAiringToday:    return (try? await tmdb.airingTodayShows()) ?? []
        case .addonCatalog(let addonID, let type, let catalogID):
            // Safe Mode skips addon catalogs so a hanging addon can't stall the home
            // screen; TMDB shelves still load.
            if SafeMode.isOn { return [] }
            guard let addon = addonStore.resolvedAddon(id: addonID) else { return [] }
            return (try? await addonClient.catalog(from: addon, type: type, catalogID: catalogID)) ?? []
        case .aiShelf(let prompt):
            return await aiResolver?(prompt) ?? []
        }
    }

    /// All live-TV catalogs across installed addons, for the Live TV screen.
    func liveTVCatalogs() -> [(addon: InstalledAddon, catalog: AddonCatalogRef)] {
        var out: [(InstalledAddon, AddonCatalogRef)] = []
        for addon in addonStore.addons where addon.isEnabled {
            for cat in addon.catalogs where cat.isLiveTV {
                out.append((addon, cat))
            }
        }
        return out
    }
}
