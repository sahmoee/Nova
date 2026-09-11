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
    let mediaIntegrations: MediaIntegrationStore
    let libraryFolders = LibraryFolderStore()
    let mediaServers: MediaServerStore
    let sonarr = SonarrStore()
    let libraryEnricher = LibraryEnricher()
    let tmdb: TMDBClient
    let omdb: OMDbClient
    let simkl: SimklClient
    let tmdbTracker: TMDBAccountClient
    let novaTracker: NovaTrackingProvider
    let episodeNotifier: EpisodeAvailabilityNotifier
    /// Aggregates Nova Tracker and the optional SIMKL/TMDB trackers. Writes fan out to all
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

    func qaDiagnostics() -> NovaQADiagnostics {
        let network = NetworkConditionMonitor.shared
        let flags = [network.isCellular ? "cellular" : nil,
                     network.isExpensive ? "metered" : nil,
                     network.isConstrained ? "low-data" : nil].compactMap { $0 }
        return NovaQADiagnostics(
            libraryItems: library.items.count,
            offlineDownloads: downloads.downloads.count,
            activeDownloads: downloads.downloads.filter { $0.state == .queued || $0.state == .downloading }.count,
            failedDownloads: downloads.downloads.filter { $0.state == .failed }.count,
            smbFolders: libraryFolders.folders.count,
            installedAddons: addonStore.addons.count,
            network: network.isOnline ? "online" : "offline",
            networkFlags: flags.isEmpty ? "none" : flags.joined(separator: ", ")
        )
    }

    /// Resolve the best playable stream for a catalog item and enqueue it for offline
    /// download. Movies pass episode = nil; series pass the chosen EpisodeInfo. Returns
    /// whether a download was started.
    @MainActor @discardableResult
    func downloadToDevice(_ item: CatalogItem, episode: EpisodeInfo? = nil) async -> Bool {
        let epRef = episode.map { EpisodeRef(season: $0.season, number: $0.number, episodeTitle: $0.title) }
        let streams = await catalog.streams(for: item.contentID, episode: epRef, preferredQuality: nil)
        for stream in streams.prefix(6) {
            guard var media = try? await catalog.makePlayable(stream: stream, catalog: item, episode: episode)
            else { continue }
            media.legalAccessConfirmed = true
            if downloads.enqueue(media) != nil { return true }
        }
        return false
    }

    init() {
        let lib = LibraryStore()
        self.library = lib
        self.mediaServers = MediaServerStore(library: lib)
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
        let mediaIntegrationStore = MediaIntegrationStore()
        self.mediaIntegrations = mediaIntegrationStore
        let tmdbClient = TMDBClient()
        self.tmdb = tmdbClient
        self.omdb = OMDbClient()
        let simklClient = SimklClient()
        self.simkl = simklClient
        let tmdbAccount = TMDBAccountClient()
        self.tmdbTracker = tmdbAccount
        let novaTrackerClient = NovaTrackingProvider()
        self.novaTracker = novaTrackerClient
        self.trackers = TrackingHub([novaTrackerClient, simklClient, tmdbAccount])
        // Pull the first-party tracker's data into the on-device cache at launch.
        Task { await novaTrackerClient.sync() }
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
            declarativeExtensions: { [weak mediaIntegrationStore] in mediaIntegrationStore?.extensions ?? [] },
            hasDebridToken: { KeychainStore.shared.realDebridToken != nil }
        )
        self.episodeNotifier = EpisodeAvailabilityNotifier(library: lib, tmdb: tmdbClient, catalog: self.catalog)

        self.shelfLoader = ShelfLoader(
            tmdb: tmdbClient,
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
        mediaServers.syncAll()

        // Refresh connected tracking providers after a backup restore. Live TV,
        // addons, and SMB reload via their own observers of the same notification.
        NotificationCenter.default.addObserver(
            forName: .novaBackupRestored, object: nil, queue: nil
        ) { [trackers, mediaServers] _ in
            Task {
                await trackers.refreshAll()
                await MainActor.run { mediaServers.syncAll() }
            }
        }
    }
}
