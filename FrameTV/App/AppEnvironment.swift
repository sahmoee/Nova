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

    // Source services.
    let realDebrid: RealDebridClient
    let directURL: DirectURLService
    let smb: SMBService

    // Phase 3: catalog, addons, metadata, scrobbling.
    let addonStore: AddonStore
    let tmdb: TMDBClient
    let trakt: TraktClient
    let openSubtitles: OpenSubtitlesClient
    let addonClient: StremioAddonClient
    let resolver: StreamResolver
    let skipProvider: SkipSegmentProvider
    let catalog: CatalogService

    init() {
        let lib = LibraryStore()
        self.library = lib
        self.progress = PlaybackProgressStore(library: lib)
        self.settings = SettingsStore()

        let rd = RealDebridClient()
        self.realDebrid = rd
        self.directURL = DirectURLService()
        self.smb = SMBService()

        let store = AddonStore()
        self.addonStore = store
        let tmdbClient = TMDBClient()
        self.tmdb = tmdbClient
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

        seedMockDataIfNeeded()

        // Seed default addons (Cinemeta + any from config) in the background.
        Task { await store.seedDefaultsIfNeeded() }
    }

    /// Seeds a few public-domain sample items the first time the app runs so the
    /// UI isn't empty. Controlled by a flag so it only happens once.
    private func seedMockDataIfNeeded() {
        guard !settings.didSeedMockData else { return }
        for item in MockData.sampleLibrary {
            library.add(item)
        }
        settings.didSeedMockData = true
    }
}
