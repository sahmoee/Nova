//
//  LiveTVView.swift
//  Nova
//
//  Lists live channels from any installed addon that exposes a tv/channel catalog,
//  and plays the selected channel. Channels stream as live HLS, so playback is not
//  resumed or scrobbled. If no live-TV addon is installed, explains how to add one.
//

import SwiftUI

struct LiveTVView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var sources: [(addon: InstalledAddon, catalog: AddonCatalogRef)] = []
    @State private var channels: [String: [CatalogItem]] = [:]   // keyed by catalog id
    @State private var loadingKeys: Set<String> = []
    @State private var playable: MediaItem?
    @State private var resolving = false
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: Theme.Spacing.md)]

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()

            if sources.isEmpty && env.liveTVSources.allChannels.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.rowGap) {
                        HStack {
                            Text("Live TV")
                                .font(Theme.Font.screenTitle())
                                .screenTitleStyle()
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Spacer()
                            NavigationLink { LiveTVSourcesView() } label: {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.appFont(20, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                    .padding(Theme.Spacing.sm)
                                    .background(Theme.Colors.card, in: Circle())
                            }
                            .novaIconStyle()
                        }
                        .padding(.horizontal, Theme.Spacing.edge)

                        playlistChannelsSection

                        ForEach(sources, id: \.catalog.id) { source in
                            channelSection(source)
                        }
                    }
                    .padding(.vertical, Theme.Spacing.lg)
                }
                #if os(iOS)
                // Pull-to-refresh reloads playlists and the programme guide (touch only).
                .refreshable {
                    await env.liveTVSources.refreshAll()
                    await loadEPG()
                }
                #endif
            }

            if resolving {
                LoadingView(message: "Tuning in…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black.opacity(0.5))
            }
        }
        .fullScreenCover(item: $playable) { item in
            // Present the player as a full-screen cover so no tab bar, sidebar,
            // or mini-bar remains visible during playback on any platform.
            NavigationStack { PlayerView(item: item) }
        }
        .alert("Couldn't play channel", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear(perform: loadSources)
        .task {
            await env.liveTVSources.refreshAll()
            await loadEPG()
        }
    }

    @State private var channelFilter = ""
    /// tvg-id -> current programme title, refreshed when the screen loads guides.
    @State private var nowPlaying: [String: String] = [:]

    @ViewBuilder private var playlistChannelsSection: some View {
        let channels = env.liveTVSources.allChannels
        if !channels.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("From Your Sources")
                    .font(.appFont(22, weight: .bold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.horizontal, Theme.Spacing.edge)

                // A filter field appears once the playlist is big enough to need one.
                if channels.count > 12 {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(Theme.Colors.textTertiary)
                        TextField("Filter channels", text: $channelFilter)
                            .font(.appFont(17))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        if !channelFilter.isEmpty {
                            Button { channelFilter = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(Theme.Spacing.sm)
                    .background(Theme.Colors.card,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .padding(.horizontal, Theme.Spacing.edge)
                }

                let filtered = channelFilter.isEmpty
                    ? channels
                    : channels.filter { $0.name.localizedCaseInsensitiveContains(channelFilter) }
                // Group channels by their M3U group-title so big playlists read as
                // organized sections (News, Sports, ...) instead of one endless grid.
                let grouped = Dictionary(grouping: filtered) { $0.group ?? "Channels" }
                let groupNames = grouped.keys.sorted()

                ForEach(groupNames, id: \.self) { group in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        if groupNames.count > 1 {
                            Text(group)
                                .font(.appFont(17, weight: .semibold))
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .padding(.horizontal, Theme.Spacing.edge)
                        }
                        LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                            ForEach(grouped[group] ?? []) { channel in
                                channelCell(channel)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.edge)
                    }
                }
            }
        }
    }

    private func channelCell(_ channel: LiveTVChannel) -> some View {
        Button {
            playable = env.liveTVSources.makePlayable(channel)
        } label: {
            VStack(spacing: 6) {
                CachedAsyncImage(url: channel.logoURL, maxPixel: 300) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(Theme.Colors.card)
                        .overlay(Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.appFont(28)).foregroundStyle(Theme.Colors.textTertiary))
                }
                .frame(height: 90)
                .frame(maxWidth: .infinity)
                .background(Theme.Colors.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                Text(channel.name)
                    .font(.appFont(13, weight: .medium))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                // Now-playing line from the source's XMLTV guide, when available.
                if let tvgID = channel.tvgID, let current = nowPlaying[tvgID] {
                    Text(current)
                        .font(.appFont(11))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(NovaListRowStyle())
    }

    /// Loads every enabled source's XMLTV guide and resolves the current programme
    /// for each channel that carries a tvg-id.
    private func loadEPG() async {
        let sources = env.liveTVSources.sources.filter { $0.isEnabled && $0.epgURL != nil }
        guard !sources.isEmpty else { return }
        for source in sources {
            if let raw = source.epgURL, let url = URL(string: raw) {
                await EPGService.shared.loadGuide(from: url)
            }
        }
        let ids = env.liveTVSources.allChannels.compactMap(\.tvgID)
        guard !ids.isEmpty else { return }
        nowPlaying = await EPGService.shared.nowPlaying(tvgIDs: ids)
    }

    private func channelSection(_ source: (addon: InstalledAddon, catalog: AddonCatalogRef)) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(source.catalog.name)
                    .font(Theme.Font.sectionTitle())
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(source.addon.name.uppercased())
                    .font(.appFont(12, weight: .bold))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.white.opacity(0.08), in: Capsule())
            }
            .padding(.horizontal, Theme.Spacing.edge)

            let key = source.catalog.id
            if let list = channels[key] {
                LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                    ForEach(list) { channel in
                        Button { play(channel) } label: { channelCard(channel) }
                            .buttonStyle(NovaListRowStyle())
                    }
                }
                .padding(.horizontal, Theme.Spacing.edge)
            } else {
                ProgressView().tint(Theme.Colors.accent)
                    .padding(.horizontal, Theme.Spacing.edge)
                    .task { await loadChannels(source) }
            }
        }
    }

    private func channelCard(_ channel: CatalogItem) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.Colors.card)
                CachedAsyncImage(url: channel.posterURL) { image in
                    image.resizable().aspectRatio(contentMode: .fit).padding(8)
                } placeholder: {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.appFont(34))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            .frame(height: 110)
            Text(channel.title)
                .font(.appFont(15, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.lg) {
            EmptyStateView(
                systemImage: "dot.radiowaves.left.and.right",
                title: "No Live TV yet",
                message: "Turn on a free channel source or add your own M3U or Xtream-codes playlist. You can also add a Stremio addon that provides live channels under Settings ▸ Addons."
            )
            NavigationLink { LiveTVSourcesView() } label: {
                Label("Choose Sources", systemImage: "slider.horizontal.3")
                    .font(.appFont(17, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.vertical, Theme.Spacing.md)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .background(Capsule().fill(.white))
            }
            .novaRowStyle()
        }
    }

    // MARK: - Loading

    private func loadSources() {
        sources = env.shelfLoader.liveTVCatalogs()
    }

    private func loadChannels(_ source: (addon: InstalledAddon, catalog: AddonCatalogRef)) async {
        let key = source.catalog.id
        guard channels[key] == nil, !loadingKeys.contains(key) else { return }
        loadingKeys.insert(key)
        let list = await env.catalog.liveChannels(addon: source.addon, catalog: source.catalog)
        channels[key] = list
        loadingKeys.remove(key)
    }

    private func play(_ channel: CatalogItem) {
        resolving = true
        Task {
            do {
                let item = try await env.catalog.makeLiveChannelPlayable(channel: channel)
                await MainActor.run { resolving = false; playable = item }
            } catch {
                await MainActor.run {
                    resolving = false
                    errorMessage = (error as? LocalizedError)?.errorDescription
                        ?? "This channel couldn't be opened."
                }
            }
        }
    }
}
