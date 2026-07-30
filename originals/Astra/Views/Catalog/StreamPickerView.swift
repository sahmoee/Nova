//
//  StreamPickerView.swift
//  Astra
//
//  Presents the ranked streams for a movie or episode. The user picks one (or
//  auto-select picks the best), Astra resolves it to a playable URL, and hands off
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
    @ObservedObject private var network = NetworkConditionMonitor.shared

    @State private var streams: [StreamOption] = []
    @State private var deadStreamIDs: Set<String> = []
    @State private var autoFailingOver = false
    @State private var lastPlayedStream: StreamOption?
    @State private var state: ViewState = .loading
    @State private var resolvingStreamID: String?
    @State private var playable: MediaItem?
    @State private var showAddonsSetup = false

    // Result filters.
    @State private var minQuality: StreamQuality? = nil      // nil = any
    @State private var selectedSource: String? = nil         // nil = all addons
    @State private var maxSizeGB: Double? = nil              // nil = any
    @State private var cachedOnly = UserDefaults.standard.bool(forKey: PrefKey.streamsCachedOnly)
    @State private var showFilters = false

    // Smart (natural-language) filter, e.g. "cached 1080p under 8GB english".
    @State private var smartFilterText = ""
    @State private var smartFilter = ParsedStreamFilter()

    // Group the list by source kind (Cloud, Torrent, SMB, Direct, Addon).
    @State private var groupBySource = true

    enum ViewState: Equatable { case loading, loaded, empty, error(String) }

    private var epRef: EpisodeRef? {
        episode.map { EpisodeRef(season: $0.season, number: $0.number, episodeTitle: $0.title) }
    }

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()

            switch state {
            case .loading:
                LoadingView(message: "Finding streams…")
            case .empty:
                EmptyStateView(
                    systemImage: emptyIcon,
                    title: emptyTitle,
                    message: emptyMessage,
                    actionTitle: emptyActionTitle,
                    action: emptyAction
                )
            case .error(let m):
                ErrorStateView(message: m, onRetry: { Task { await load() } }, onBack: { dismiss() })
            case .loaded:
                content
            }
        }
        .navigationDestination(item: $playable) { item in
            PlayerView(item: item, series: catalog.isSeries ? catalog : nil, onStreamExpired: {
                // The stream the player was using died. Mark it and auto-play the next.
                if let dead = lastPlayedStream { markDead(dead) }
                if let next = nextCandidate() {
                    Task { await play(next) }
                }
            })
        }
        .navigationDestination(isPresented: $showAddonsSetup) {
            AddonsView()
        }
        .task { await load() }
    }

    private var titleLine: String {
        if let episode { return "\(catalog.title) · \(episode.label)" }
        return catalog.title
    }

    /// The cause of an empty result drives the icon, message, and suggested action.
    private enum EmptyCause { case safeMode, noAddons, noResults }
    private var emptyCause: EmptyCause {
        if SafeMode.isOn { return .safeMode }
        if env.addonStore.streamAddons.isEmpty { return .noAddons }
        return .noResults
    }

    private var emptyIcon: String {
        switch emptyCause {
        case .safeMode:  return "exclamationmark.shield"
        case .noAddons:  return "puzzlepiece.extension"
        case .noResults: return "magnifyingglass"
        }
    }

    private var emptyTitle: String {
        switch emptyCause {
        case .safeMode:  return "Safe Mode is on"
        case .noAddons:  return "No stream sources yet"
        case .noResults: return "No streams found"
        }
    }

    private var emptyMessage: String {
        switch emptyCause {
        case .safeMode:
            return "Addons are disabled while Safe Mode is on, so no streams can be found. Turn off Safe Mode to use your addons again."
        case .noAddons:
            return "Install a stream addon to find streams for this title. AIOStreams and Comet are supported."
        case .noResults:
            return "No addon returned a stream for this title. Try a different quality, or check that your addons are working."
        }
    }

    private var emptyActionTitle: String? {
        switch emptyCause {
        case .safeMode:  return "Turn Off Safe Mode"
        case .noAddons:  return "Set Up Addons"
        case .noResults: return "Check Addons"
        }
    }

    private var emptyAction: (() -> Void)? {
        switch emptyCause {
        case .safeMode:
            return { settings.safeMode = false; Task { await load() } }
        case .noAddons, .noResults:
            return { showAddonsSetup = true }
        }
    }


    /// A one-tap minimum-quality chip. Selecting the active chip (or Any) clears it.
    private func qualityChip(_ quality: StreamQuality?, label: String) -> some View {
        let isActive = minQuality == quality
        return Button {
            withAnimation { minQuality = quality }
        } label: {
            Text(label)
                .font(.appFont(16, weight: .semibold))
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 7)
                .background(Capsule().fill(isActive ? Theme.Colors.accent : Theme.Colors.card))
                .foregroundStyle(isActive ? .white : Theme.Colors.textSecondary)
        }
        .buttonStyle(AstraChipButtonStyle())
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
                    .astraRowStyle()
                    Button { withAnimation { showFilters.toggle() } } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "line.3.horizontal.decrease.circle\(anyFilterActive ? ".fill" : "")")
                            Text("Filter")
                        }
                        .font(.appFont(18, weight: .semibold))
                        .foregroundStyle(anyFilterActive ? Theme.Colors.accent : Theme.Colors.textSecondary)
                    }
                    .astraRowStyle()
                }

                if showFilters { filterBar }

                // Quick quality chips: one-tap minimum-quality filtering without
                // opening the full filter sheet. "Any" clears it.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.sm) {
                        qualityChip(nil, label: "Any")
                        ForEach([StreamQuality.uhd4k, .fhd1080, .hd720], id: \.self) { q in
                            qualityChip(q, label: "\(q.rawValue)+")
                        }
                        Button {
                            withAnimation { cachedOnly.toggle() }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: cachedOnly ? "bolt.fill" : "bolt")
                                Text("Cached")
                            }
                            .font(.appFont(16, weight: .semibold))
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(cachedOnly ? Theme.Colors.accent : Theme.Colors.card))
                            .foregroundStyle(cachedOnly ? .white : Theme.Colors.textSecondary)
                        }
                        .buttonStyle(AstraChipButtonStyle())
                    }
                }

                networkBanner

                if groupBySource {
                    ForEach(groupedStreams, id: \.0) { group in
                        sourceGroupHeader(group.0, count: group.1.count)
                        ForEach(group.1) { stream in
                            streamRow(stream, labels: streamLabels[stream.id] ?? [])
                        }
                    }
                } else {
                    ForEach(streamsPreviousFirst) { stream in
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
            // Streams that already failed to resolve this session are excluded.
            if deadStreamIDs.contains(s.id) { return false }
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

    /// filteredStreams with the previously-used stream pulled to the front, for the
    /// flat (ungrouped) list. Grouped mode gets its own "Continue" section instead.
    private var streamsPreviousFirst: [StreamOption] {
        guard let prevID = previousEntry?.stream.id,
              let idx = filteredStreams.firstIndex(where: { $0.id == prevID }) else {
            return filteredStreams
        }
        var list = filteredStreams
        let prev = list.remove(at: idx)
        list.insert(prev, at: 0)
        return list
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
        var result: [(String, [StreamOption])] = []
        // Continue: the exact stream last used for this title, surfaced at the very
        // top as a one-tap resume.
        if let prevID = previousEntry?.stream.id,
           let prev = filteredStreams.first(where: { $0.id == prevID }) {
            result.append(("Continue where you left off", [prev]))
        }
        // Recommended: the top few streams overall (already rank-sorted in
        // filteredStreams), surfaced first so the best pick is immediate.
        let recommended = Array(filteredStreams.prefix(3)).filter { $0.id != previousEntry?.stream.id }
        if !recommended.isEmpty {
            result.append(("Recommended", recommended))
        }
        result += order.compactMap { kind in
            guard let items = grouped[kind], !items.isEmpty else { return nil }
            return (sourceGroupTitle(kind), items)
        }
        return result
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

    /// Advisory banner when the network looks limited (cellular / metered / Low Data),
    /// suggesting Bandwidth Saver. One-tap enables it; the app then prefers smaller,
    /// cached streams.
    @ViewBuilder
    private var networkBanner: some View {
        if let reason = network.suggestionReason, !settings.bandwidthSaver {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "wifi.exclamationmark")
                    .foregroundStyle(Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bandwidth Saver suggested")
                        .font(.appFont(16, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("\(reason). Prefer smaller, cached streams to avoid heavy data use.")
                        .font(.appFont(14))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                Button("Enable") { settings.bandwidthSaver = true }
                    .font(.appFont(15, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
            }
            .padding(Theme.Spacing.md)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
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
                .onChange(of: cachedOnly) { _, new in
            // The cached-only choice is sticky across titles and launches.
            UserDefaults.standard.set(new, forKey: PrefKey.streamsCachedOnly)
        }
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

    /// The remembered stream entry for this movie/episode, if any.
    private var previousEntry: StreamHistoryEntry? {
        StreamHistoryStore.shared.entry(catalogKey: catalog.contentID.stableKey, episode: epRef)
    }

    /// A pill marking the stream the user last played, with a relative "Used … ago".
    private func previousUsedBadge(_ date: Date) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "clock.arrow.circlepath")
            Text(StreamHistoryStore.usedAgoText(date))
        }
        .font(.appFont(13, weight: .semibold))
        .foregroundStyle(Theme.Colors.accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(Theme.Colors.accent.opacity(0.15)))
        .overlay(Capsule().strokeBorder(Theme.Colors.accent.opacity(0.5), lineWidth: 1))
    }

    private func streamRow(_ stream: StreamOption, labels: [StreamRanker.StreamLabel]) -> some View {
        Button { Task { await play(stream) } } label: {
            HStack(spacing: Theme.Spacing.md) {
                // Quality chip.
                Text(stream.quality.rawValue)
                    .font(.appFont(18, weight: .bold))
                    .frame(width: 72)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(colors: [qualityColor(stream.quality),
                                                qualityColor(stream.quality).opacity(0.75)],
                                       startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 6) {
                    // "Previously used" marker: if this is the exact stream the user
                    // last played for this title, show when — e.g. "Used 6 hrs ago".
                    if let entry = previousEntry, entry.stream.id == stream.id {
                        previousUsedBadge(entry.lastUsed)
                    }
                    // Best-match labels (Best Overall, Fastest Start, etc.). Uses a
                    // wrapping layout so multiple labels flow onto new lines instead of
                    // being squeezed into vertical text.
                    if !labels.isEmpty {
                        WrapFlowLayout(spacing: 6, lineSpacing: 6) {
                            ForEach(labels, id: \.rawValue) { label in
                                matchLabel(label)
                            }
                        }
                    }
                    // Playback confidence: an instant plain-language read.
                    confidenceBadge(StreamRanker.confidence(stream))
                    Text(stream.rawTitle)
                        .font(.appFont(20, weight: .medium))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
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
            .padding(.vertical, Theme.Spacing.sm)
            .frame(minHeight: Theme.minTouchTarget)
            .contentShape(Rectangle())
        }
        .astraRowStyle()
        .disabled(resolvingStreamID != nil)
    }

    /// A single "Best Match" badge. Positive labels use the accent; the low-seeders
    /// warning uses a cautionary orange.
    private func matchLabel(_ label: StreamRanker.StreamLabel) -> some View {
        HStack(spacing: 4) {
            Image(systemName: label.systemImage)
            Text(label.rawValue)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(.appFont(13, weight: .bold))
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(
            (label.isWarning ? Color.orange : Theme.Colors.accent).opacity(0.18),
            in: Capsule()
        )
        .foregroundStyle(label.isWarning ? Color.orange : Theme.Colors.accent)
    }

    private func confidenceBadge(_ c: StreamRanker.PlaybackConfidence) -> some View {
        let color: Color
        switch c {
        case .readyToPlay:      color = Theme.Colors.success
        case .likelyCompatible: color = Theme.Colors.accent
        case .mayNeedVLC:       color = Color.orange
        case .slowSource:       color = Color.orange
        case .lowConfidence:    color = Theme.Colors.textTertiary
        }
        return HStack(spacing: 5) {
            Image(systemName: c.systemImage)
            Text(c.rawValue)
        }
        .font(.appFont(14, weight: .semibold))
        .foregroundStyle(color)
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
        // manual list order respects source, size, seeders, language, codec, HDR,
        // the source fallback chain, and the user's addon order.
        let prefs = settings.streamPreferences(addonOrder: env.addonStore.addons.map(\.name))
        streams = StreamRanker.rank(StreamRanker.dedupeByIdentity(found), preferences: prefs)
        if found.isEmpty { state = .empty; return }

        // Batch Real-Debrid instant-availability: one request marks every torrent
        // hash that is actually cached, instead of trusting addon labels alone.
        await refreshInstantAvailability(preferences: prefs)

        // Prefer the previously-used stream when resuming: if the user played a
        // specific source before and it's still in the results, reuse it instead of
        // re-running generic auto-select. Skipped when the user explicitly asked to
        // pick manually.
        if !forceManual,
           let previous = StreamHistoryStore.shared.entry(catalogKey: catalog.contentID.stableKey,
                                                          episode: epRef),
           let match = streams.first(where: { $0.id == previous.stream.id && !deadStreamIDs.contains($0.id) }) {
            state = .loaded
            await play(match)
            return
        }

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
            lastPlayedStream = stream
            // Remember this exact stream (and when) so Resume reuses it and the picker
            // can mark it "Used … ago".
            StreamHistoryStore.shared.record(stream,
                                             catalogKey: catalog.contentID.stableKey,
                                             episode: epRef)
            playable = item
        } catch {
            // This stream failed to resolve — mark it dead, drop it from the list, and
            // automatically try the next best candidate. Only surface an error if
            // nothing is left to try.
            markDead(stream)
            if let next = nextCandidate() {
                autoFailingOver = true
                await play(next)
            } else {
                autoFailingOver = false
                state = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    /// One batched Real-Debrid check upgrades isCached on streams whose infohash is
    /// in the user's cloud, then re-ranks so cached copies float up.
    private func refreshInstantAvailability(preferences: StreamRanker.StreamPreferences) async {
        guard KeychainStore.shared.realDebridToken != nil else { return }
        let hashes = Array(Set(streams.compactMap { $0.isCached ? nil : $0.infoHash?.lowercased() }))
        guard !hashes.isEmpty,
              let available = try? await env.realDebrid.instantAvailability(hashes: hashes),
              !available.isEmpty else { return }
        var updated = streams
        for idx in updated.indices {
            if let hash = updated[idx].infoHash?.lowercased(), available.contains(hash) {
                updated[idx].isCached = true
                updated[idx].sourceKind = .cloud
            }
        }
        streams = StreamRanker.rank(updated, preferences: preferences)
    }

    /// Marks a stream dead so it is filtered out and never auto-selected again this
    /// session.
    private func markDead(_ stream: StreamOption) {
        deadStreamIDs.insert(stream.id)
        streams.removeAll { $0.id == stream.id }
    }

    /// The next best still-alive stream to try, honoring the current filters and
    /// preferring cached/instant sources first.
    private func nextCandidate() -> StreamOption? {
        filteredStreams.first { !deadStreamIDs.contains($0.id) }
    }
}
