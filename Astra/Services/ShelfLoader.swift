//
//  ShelfLoader.swift
//  Astra
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

    // Short-lived cache so Home and Discover share results within a session.
    private let cache = TTLCache<String, [CatalogItem]>(ttl: 60 * 10)   // 10 min

    init(tmdb: TMDBClient, trakt: TraktClient,
         addonClient: StremioAddonClient, addonStore: AddonStore) {
        self.tmdb = tmdb
        self.trakt = trakt
        self.addonClient = addonClient
        self.addonStore = addonStore
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
            let result = await load(shelf.kind)
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

    private func cacheKey(for kind: ShelfKind) -> String {
        switch kind {
        case .addonCatalog(let a, let t, let c): return "addon:\(a):\(t):\(c)"
        default: return String(describing: kind)
        }
    }

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
            guard let addon = addonStore.addons.first(where: { $0.id == addonID }) else { return [] }
            return (try? await addonClient.catalog(from: addon, type: type, catalogID: catalogID)) ?? []
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
