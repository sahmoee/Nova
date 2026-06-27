//
//  StreamPickerView.swift
//  FrameTV
//
//  Presents the ranked streams for a movie or episode. The user picks one (or
//  auto-select picks the best), FrameTV resolves it to a playable URL, and hands off
//  to the player. Shows quality, size, seeders, source, and a cached badge.
//

import SwiftUI

struct StreamPickerView: View {
    let catalog: CatalogItem
    let episode: EpisodeInfo?

    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var streams: [StreamOption] = []
    @State private var state: ViewState = .loading
    @State private var resolvingStreamID: String?
    @State private var playable: MediaItem?

    enum ViewState: Equatable { case loading, loaded, empty, error(String) }

    private var epRef: EpisodeRef? {
        episode.map { EpisodeRef(season: $0.season, number: $0.number, episodeTitle: $0.title) }
    }

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            switch state {
            case .loading:
                LoadingView(message: "Finding streams…")
            case .empty:
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    title: "No streams found",
                    message: emptyMessage
                )
            case .error(let m):
                ErrorStateView(message: m, onRetry: { Task { await load() } }, onBack: { dismiss() })
            case .loaded:
                content
            }
        }
        .navigationDestination(item: $playable) { item in
            PlayerView(item: item, series: catalog.isSeries ? catalog : nil)
        }
        .task { await load() }
    }

    private var titleLine: String {
        if let episode { return "\(catalog.title) · \(episode.label)" }
        return catalog.title
    }

    private var emptyMessage: String {
        if env.addonStore.streamAddons.isEmpty {
            return "Add a stream addon (Sources ▸ Addons) to find streams. AIOStreams and Comet are supported."
        }
        return "No addon returned a stream for this title. Try another quality or check your addons."
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text(titleLine)
                    .font(Theme.Font.screenTitle())
                    .screenTitleStyle()
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("\(streams.count) streams")
                    .font(.appFont(20))
                    .foregroundStyle(Theme.Colors.textSecondary)

                ForEach(streams) { stream in
                    streamRow(stream)
                }
            }
            .padding(Theme.Spacing.edge)
            .frame(maxWidth: Theme.contentMaxWidth(1200), alignment: .leading)
        }
    }

    private func streamRow(_ stream: StreamOption) -> some View {
        Button { Task { await play(stream) } } label: {
            HStack(spacing: Theme.Spacing.md) {
                // Quality chip.
                Text(stream.quality.rawValue)
                    .font(.appFont(18, weight: .bold))
                    .frame(width: 72)
                    .padding(.vertical, 8)
                    .background(qualityColor(stream.quality), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 4) {
                    Text(stream.rawTitle)
                        .font(.appFont(20, weight: .medium))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(2)
                    HStack(spacing: Theme.Spacing.sm) {
                        Label(stream.addonName, systemImage: "puzzlepiece.extension")
                        if let size = stream.sizeDisplay { Text(size) }
                        if let seeders = stream.seeders { Label("\(seeders)", systemImage: "arrow.up.circle") }
                        if stream.isCached {
                            Label("Cached", systemImage: "bolt.fill")
                                .foregroundStyle(Theme.Colors.success)
                        }
                    }
                    .font(.appFont(15))
                    .foregroundStyle(Theme.Colors.textTertiary)
                }
                Spacer()
                if resolvingStreamID == stream.id {
                    ProgressView().tint(Theme.Colors.accent)
                } else {
                    Image(systemName: "play.circle.fill")
                        .font(.appFont(30))
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(resolvingStreamID != nil)
    }

    private func qualityColor(_ q: StreamQuality) -> Color {
        switch q {
        case .uhd4k:   return Theme.Colors.accent
        case .fhd1080: return Theme.Colors.accentSecondary
        case .hd720:   return Theme.Colors.success
        case .sd480:   return Theme.Colors.warning
        case .cam:     return Theme.Colors.error
        case .unknown: return Theme.Colors.textTertiary
        }
    }

    // MARK: - Actions

    private func load() async {
        state = .loading
        // Progressive: show results as each addon responds. As soon as we have
        // any streams, flip to the loaded state so the user sees them building up.
        let found = await env.catalog.streamsProgressive(
            for: catalog.contentID,
            episode: epRef,
            preferredQuality: settings.preferredStreamQuality,
            onPartial: { partial in
                self.streams = partial
                if !partial.isEmpty, self.state == .loading {
                    self.state = .loaded
                }
            }
        )
        streams = found
        if found.isEmpty { state = .empty; return }

        // Auto-select path.
        if settings.autoSelectStream,
           let best = StreamRanker.autoSelect(found,
                                              preferredQuality: settings.preferredStreamQuality,
                                              requireCached: settings.requireCachedStreams) {
            state = .loaded
            await play(best)
        } else {
            state = .loaded
        }
    }

    private func play(_ stream: StreamOption) async {
        resolvingStreamID = stream.id
        defer { resolvingStreamID = nil }
        do {
            let item = try await env.catalog.makePlayable(
                stream: stream, catalog: catalog, episode: episode
            )
            env.library.add(item)
            playable = item
        } catch {
            state = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
