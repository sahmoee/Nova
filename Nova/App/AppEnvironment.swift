//
//  AppEnvironment.swift
//  Nova
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
    let downloads: DownloadManager

    // Phase 3: catalog, addons, metadata, scrobbling.
    let addonStore: AddonStore
    let liveTVSources = LiveTVSourceStore()
    let libraryFolders = LibraryFolderStore()
    let libraryEnricher = LibraryEnricher()
    let tmdb: TMDBClient
    let omdb: OMDbClient
    let trakt: TraktClient
    let simkl: SimklClient
    let tmdbTracker: TMDBAccountClient
    let novaTracker: NovaTrackingProvider
    let episodeNotifier: EpisodeAvailabilityNotifier
    /// Aggregates every optional tracker (Trakt, SIMKL, TMDB). Writes fan out to all
    /// connected trackers; reads merge across them. Use this instead of a single
    /// service for watchlist/trending/scrobble.
    let trackers: TrackingHub
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

        let rd = RealDebridClient()
        self.realDebrid = rd
        self.directURL = DirectURLService()
        self.smb = SMBService()
        self.downloads = DownloadManager()

        let store = AddonStore()
        self.addonStore = store
        let tmdbClient = TMDBClient()
        self.tmdb = tmdbClient
        self.omdb = OMDbClient()
        let traktClient = TraktClient()
        self.trakt = traktClient
        let simklClient = SimklClient()
        self.simkl = simklClient
        let tmdbAccount = TMDBAccountClient()
        self.tmdbTracker = tmdbAccount
        let novaTrackerClient = NovaTrackingProvider()
        self.novaTracker = novaTrackerClient
        self.trackers = TrackingHub([novaTrackerClient, traktClient, simklClient, tmdbAccount])
        // Pull the first-party tracker's data into the on-device cache at launch.
        Task { await novaTrackerClient.sync() }
        self.episodeNotifier = EpisodeAvailabilityNotifier(library: lib, tmdb: tmdbClient, catalog: self.catalog)
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
        // Let AI-generated shelves resolve through the AI service.
        self.shelfLoader.aiResolver = { [weak aiSearch = self.aiSearch] prompt in
            guard let aiSearch else { return [] }
            return (try? await aiSearch.run(.buildShelf, userText: prompt)) ?? []
        }

        // Library intentionally starts empty — it fills as the user plays or
        // favorites content. No sample/placeholder items are seeded.

        // Seed default addons (Cinemeta + any from config) in the background.
        Task { await store.seedDefaultsIfNeeded() }

        // After a backup restore, the Trakt access/refresh tokens are written to the
        // Keychain but the client never re-checks them. Refresh + validate so a
        // restored login is actually usable (or clearly marked expired) rather than
        // just appearing connected. Live TV, addons, and SMB reload via their own
        // observers of the same notification.
        NotificationCenter.default.addObserver(
            forName: .novaBackupRestored, object: nil, queue: nil
        ) { [trackers] _ in
            Task { await trackers.refreshAll() }
        }
    }
}
