//
//  AppEnvironment.swift
//  FrameTV
//
//  Composition root. Owns the shared services so views can pull what they need
//  via @EnvironmentObject. Seeds sample data and default addons on first run.
//

import SwiftUI

@MainActor
final class AppEnvironment: ObservableObject {

    let library: LibraryStore
    let progress: PlaybackProgressStore
    let settings: SettingsStore
    /// Per-show binge settings (autoplay/skip overrides).
    let showSettings: ShowSettingsStore

    // Source services.
    let realDebrid: RealDebridClient
    let directURL: DirectURLService
    let smb: SMBService

    // Phase 3: catalog, addons, metadata, scrobbling.
    let addonStore: AddonStore
    let liveTVSources: LiveTVSourceStore
    let tmdb: TMDBClient
    let omdb: OMDbClient
    let trakt: TraktClient
    let openSubtitles: OpenSubtitlesClient
    let addonClient: StremioAddonClient
    let resolver: StreamResolver
    let skipProvider: SkipSegmentProvider
    let catalog: CatalogService
    let shelfLoader: ShelfLoader
    let aiSearch: AISearchService

    init() {
        let lib = LibraryStore()
        self.library = lib
        self.progress = PlaybackProgressStore(library: lib)
        self.settings = SettingsStore()
        self.showSettings = ShowSettingsStore()
        self.liveTVSources = LiveTVSourceStore()

        let rd = RealDebridClient()
        self.realDebrid = rd
        self.directURL = DirectURLService()
        self.smb = SMBService()

        let store = AddonStore()
        self.addonStore = store
        let tmdbClient = TMDBClient()
        self.tmdb = tmdbClient
        self.omdb = OMDbClient()
        self.trakt = TraktClient()
        let os = OpenSubtitlesClient()
        self.openSubtitles = os
        let addonCli = StremioAddonClient()
        self.addonClient = addonCli
        let streamResolver = StreamResolver(realDebrid: rd)
        self.resolver = streamResolver
        let skip = SkipSegmentProvider()
        self.skipProvider = skip

        self.catalog = CatalogService(
            tmdb: tmdbClient,
            addonClient: addonCli,
            addonStore: store,
            resolver: streamResolver,
            openSubtitles: os,
            skipProvider: skip,
            hasDebridToken: { KeychainStore.shared.realDebridToken != nil }
        )

        self.shelfLoader = ShelfLoader(
            tmdb: tmdbClient,
            trakt: self.trakt,
            addonClient: addonCli,
            addonStore: store
        )

        self.aiSearch = AISearchService(tmdb: tmdbClient)

        // Library intentionally starts empty — it fills as the user plays or
        // favorites content. No sample/placeholder items are seeded.

        // Seed default addons (Cinemeta + any from config) in the background.
        Task { await store.seedDefaultsIfNeeded() }
    }
}
