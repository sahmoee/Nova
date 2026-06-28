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

    // Result filters.
    @State private var minQuality: StreamQuality? = nil      // nil = any
    @State private var selectedSource: String? = nil         // nil = all addons
    @State private var maxSizeGB: Double? = nil              // nil = any
    @State private var cachedOnly = false
    @State private var showFilters = false

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

                HStack {
                    Text(filterSummary)
                        .font(.appFont(20))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    Button { withAnimation { showFilters.toggle() } } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "line.3.horizontal.decrease.circle\(anyFilterActive ? ".fill" : "")")
                            Text("Filter")
                        }
                        .font(.appFont(18, weight: .semibold))
                        .foregroundStyle(anyFilterActive ? Theme.Colors.accent : Theme.Colors.textSecondary)
                    }
                    .frameRowStyle()
                }

                if showFilters { filterBar }

                ForEach(filteredStreams) { stream in
                    streamRow(stream)
                }

                if filteredStreams.isEmpty {
                    Text("No streams match these filters.")
                        .font(.appFont(20))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .padding(.top, Theme.Spacing.lg)
                }
            }
            .padding(Theme.Spacing.edge)
            .frame(maxWidth: Theme.contentMaxWidth(1200), alignment: .leading)
        }
    }

    // MARK: - Filtering

    /// Streams after applying the active filters, preserving rank order.
    private var filteredStreams: [StreamOption] {
        streams.filter { s in
            if let minQuality, s.quality.rank < minQuality.rank { return false }
            if let selectedSource, s.addonName != selectedSource { return false }
            if cachedOnly, !s.isCached { return false }
            if let maxSizeGB, let bytes = s.sizeBytes {
                if Double(bytes) > maxSizeGB * 1_073_741_824 { return false }
            }
            return true
        }
    }

    private var availableSources: [String] {
        Array(Set(streams.map(\.addonName))).sorted()
    }

    private var anyFilterActive: Bool {
        minQuality != nil || selectedSource != nil || maxSizeGB != nil || cachedOnly
    }

    private var filterSummary: String {
        let n = filteredStreams.count
        let total = streams.count
        return n == total ? "\(total) streams" : "\(n) of \(total) streams"
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // Quality.
            filterGroup("Minimum Quality") {
                chip("Any", active: minQuality == nil) { minQuality = nil }
                ForEach([StreamQuality.uhd4k, .fhd1080, .hd720, .sd480], id: \.self) { q in
                    chip(q.rawValue, active: minQuality == q) { minQuality = q }
                }
            }
            // Source.
            if availableSources.count > 1 {
                filterGroup("Source") {
                    chip("All", active: selectedSource == nil) { selectedSource = nil }
                    ForEach(availableSources, id: \.self) { src in
                        chip(src, active: selectedSource == src) { selectedSource = src }
                    }
                }
            }
            // Max size.
            filterGroup("Max Size") {
                chip("Any", active: maxSizeGB == nil) { maxSizeGB = nil }
                ForEach([2.0, 5.0, 10.0, 20.0], id: \.self) { gb in
                    chip("\(Int(gb)) GB", active: maxSizeGB == gb) { maxSizeGB = gb }
                }
            }
            // Cached only.
            chip("Instant (cached) only", active: cachedOnly) { cachedOnly.toggle() }

            if anyFilterActive {
                Button("Clear filters") {
                    minQuality = nil; selectedSource = nil; maxSizeGB = nil; cachedOnly = false
                }
                .font(.appFont(17, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent)
                .padding(.top, 4)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
    }

    private func filterGroup<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.appFont(16, weight: .semibold))
                .foregroundStyle(Theme.Colors.textTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { content() }
            }
        }
    }

    private func chip(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.appFont(17, weight: .semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(active ? Theme.Colors.accent : Color.white.opacity(0.10),
                            in: Capsule())
                .foregroundStyle(active ? .white : Theme.Colors.textPrimary)
        }
        .buttonStyle(.plain)
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

                VStack(alignment: .leading, spacing: 6) {
                    Text(stream.rawTitle)
                        .font(.appFont(20, weight: .medium))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(2)
                    // Source health badges (Cached, Fast, 4K, HDR, Dolby, Low Seed
                    // Risk, Local SMB, Cloud), parsed from the stream's title.
                    if !stream.badges.isEmpty {
                        FlowBadges(badges: stream.badges)
                    }
                    HStack(spacing: Theme.Spacing.sm) {
                        Label(stream.addonName, systemImage: "puzzlepiece.extension")
                        if let size = stream.sizeDisplay { Text(size) }
                        if let seeders = stream.seeders { Label("\(seeders)", systemImage: "arrow.up.circle") }
                        if stream.videoCodec != .unknown { Text(stream.videoCodec.rawValue) }
                        if let ch = stream.audioChannels { Text(ch) }
                        if let lang = stream.languages.first { Text(lang) }
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
            .padding(.vertical, Theme.Spacing.xs)
            .contentShape(Rectangle())
        }
        .frameRowStyle()
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
