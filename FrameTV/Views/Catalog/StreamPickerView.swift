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
    /// When true, the auto-select shortcut is skipped and the list is always shown,
    /// even if the user has auto-select enabled (used by the "Choose Stream" button).
    var forceManual: Bool = false

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

    // Smart (natural-language) filter, e.g. "cached 1080p under 8GB english".
    @State private var smartFilterText = ""
    @State private var smartFilter = ParsedStreamFilter()

    // Group the list by source kind (Cloud, Torrent, SMB, Direct, Addon).
    @State private var groupBySource = false

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
                    Button { withAnimation { groupBySource.toggle() } } label: {
                        HStack(spacing: 6) {
                            Image(systemName: groupBySource ? "square.stack.3d.up.fill" : "square.stack.3d.up")
                            Text("Group")
                        }
                        .font(.appFont(18, weight: .semibold))
                        .foregroundStyle(groupBySource ? Theme.Colors.accent : Theme.Colors.textSecondary)
                    }
                    .frameRowStyle()
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

                if groupBySource {
                    ForEach(groupedStreams, id: \.0) { group in
                        sourceGroupHeader(group.0, count: group.1.count)
                        ForEach(group.1) { stream in
                            streamRow(stream, labels: streamLabels[stream.id] ?? [])
                        }
                    }
                } else {
                    ForEach(filteredStreams) { stream in
                        streamRow(stream, labels: streamLabels[stream.id] ?? [])
                    }
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

    /// Streams after applying the active filters, preserving rank order. Combines the
    /// chip filters with any active smart (natural-language) filter.
    private var filteredStreams: [StreamOption] {
        streams.filter { s in
            // Chip filters.
            if let minQuality, s.quality.rank < minQuality.rank { return false }
            if let selectedSource, s.addonName != selectedSource { return false }
            if cachedOnly, !s.isCached { return false }
            if let maxSizeGB, let bytes = s.sizeBytes {
                if Double(bytes) > maxSizeGB * 1_073_741_824 { return false }
            }
            // Smart filter (natural language).
            if let q = smartFilter.minQuality, s.quality.rank < q.rank { return false }
            if smartFilter.cachedOnly, !s.isCached { return false }
            if let gb = smartFilter.maxSizeGB, let bytes = s.sizeBytes {
                if Double(bytes) > gb * 1_073_741_824 { return false }
            }
            if let lang = smartFilter.language,
               !s.languages.contains(where: { $0.uppercased() == lang }) { return false }
            if smartFilter.codecPreferred, s.videoCodec == .avc || s.videoCodec == .unknown { return false }
            if smartFilter.hdrOnly, s.hdr.rank == 0 { return false }
            return true
        }
    }

    /// "Best Match" superlative labels (Best Overall, Fastest Start, etc.), computed
    /// across the full stream set using the user's preferences and keyed by stream id.
    private var streamLabels: [String: [StreamRanker.StreamLabel]] {
        StreamRanker.labels(for: streams, preferences: settings.streamPreferences)
    }

    /// Streams grouped by source kind, in a sensible order (Cloud, Torrent, SMB,
    /// Direct, then anything else), preserving rank order within each group. Returns
    /// pairs of (group title, streams).
    private var groupedStreams: [(String, [StreamOption])] {
        let order: [SourceKind] = [.cloud, .torrent, .localSMB, .directURL, .liveTV, .unknown]
        let grouped = Dictionary(grouping: filteredStreams, by: { $0.sourceKind })
        return order.compactMap { kind in
            guard let items = grouped[kind], !items.isEmpty else { return nil }
            return (sourceGroupTitle(kind), items)
        }
    }

    private func sourceGroupTitle(_ kind: SourceKind) -> String {
        switch kind {
        case .cloud:     return "Cloud / Debrid"
        case .torrent:   return "Torrents"
        case .localSMB:  return "Local SMB"
        case .directURL: return "Direct URLs"
        case .liveTV:    return "Live TV"
        case .unknown:   return "Other"
        }
    }

    private func sourceGroupHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.appFont(20, weight: .bold))
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("\(count)")
                .font(.appFont(15, weight: .semibold))
                .foregroundStyle(Theme.Colors.textTertiary)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Color.white.opacity(0.08), in: Capsule())
            Spacer()
        }
        .padding(.top, Theme.Spacing.md)
    }

    private var availableSources: [String] {
        Array(Set(streams.map(\.addonName))).sorted()
    }

    private var anyFilterActive: Bool {
        minQuality != nil || selectedSource != nil || maxSizeGB != nil || cachedOnly
            || !smartFilter.isEmpty
    }

    private var filterSummary: String {
        let n = filteredStreams.count
        let total = streams.count
        return n == total ? "\(total) streams" : "\(n) of \(total) streams"
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // Smart (natural-language) filter.
            VStack(alignment: .leading, spacing: 6) {
                Text("Smart Filter")
                    .font(.appFont(16, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Theme.Colors.accent)
                    TextField("e.g. cached 1080p under 8GB english", text: $smartFilterText)
                        .font(.appFont(18))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        #endif
                        .onSubmit { smartFilter = StreamFilterParser.parse(smartFilterText) }
                    if !smartFilterText.isEmpty {
                        Button {
                            smartFilterText = ""
                            smartFilter = ParsedStreamFilter()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Theme.Spacing.sm)
                .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                // Re-parse as the user types so the list updates live.
                .onChange(of: smartFilterText) { _, new in
                    smartFilter = StreamFilterParser.parse(new)
                }
            }

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
                    smartFilterText = ""; smartFilter = ParsedStreamFilter()
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

    private func streamRow(_ stream: StreamOption, labels: [StreamRanker.StreamLabel]) -> some View {
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
                    // Best-match labels (Best Overall, Fastest Start, etc.).
                    if !labels.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(labels, id: \.rawValue) { label in
                                matchLabel(label)
                            }
                        }
                    }
                    Text(stream.rawTitle)
                        .font(.appFont(20, weight: .medium))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(2)
                    // "Why this stream?" — a plain-language reason line for the top pick.
                    if labels.contains(.bestOverall) {
                        let reasons = StreamRanker.explain(stream, preferences: settings.streamPreferences)
                        Text("Why: " + reasons.prefix(4).joined(separator: " · "))
                            .font(.appFont(14))
                            .foregroundStyle(Theme.Colors.accent)
                            .lineLimit(2)
                    }
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

    /// A single "Best Match" badge. Positive labels use the accent; the low-seeders
    /// warning uses a cautionary orange.
    private func matchLabel(_ label: StreamRanker.StreamLabel) -> some View {
        HStack(spacing: 4) {
            Image(systemName: label.systemImage)
            Text(label.rawValue)
        }
        .font(.appFont(13, weight: .bold))
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(
            (label.isWarning ? Color.orange : Theme.Colors.accent).opacity(0.18),
            in: Capsule()
        )
        .foregroundStyle(label.isWarning ? Color.orange : Theme.Colors.accent)
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
        // Re-rank the complete set using the user's full streaming preferences so the
        // manual list order respects source, size, seeders, language, codec, and HDR,
        // not just quality.
        streams = StreamRanker.rank(found, preferences: settings.streamPreferences)
        if found.isEmpty { state = .empty; return }

        // Auto-select path (skipped when the user explicitly chose to pick manually).
        if settings.autoSelectStream, !forceManual,
           let best = StreamRanker.autoSelect(found,
                                              preferences: settings.streamPreferences,
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
