//
//  ContentDetailView.swift
//  FrameTV
//
//  Detail screen for a catalog item. For movies it shows artwork, overview, and a
//  "Find Streams" action. For series it hydrates seasons/episodes and lists them,
//  with each episode routing into the stream picker.
//

import SwiftUI

struct ContentDetailView: View {
    let initialItem: CatalogItem

    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dynamicAccent) private var accent
    @State private var item: CatalogItem
    @State private var isHydrating = false
    @State private var selectedSeason: Int?
    @State private var streamTarget: StreamTarget?
    @State private var favoriteRefresh = false   // toggles to re-read favorite state

    init(item: CatalogItem) {
        self.initialItem = item
        _item = State(initialValue: item)
    }

    /// Identifies what the stream picker should look for.
    struct StreamTarget: Identifiable, Hashable {
        let id = UUID()
        let catalog: CatalogItem
        let episode: EpisodeInfo?
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                if item.isSeries {
                    seriesBody
                } else {
                    movieBody
                }
            }
            .padding(Theme.Spacing.edge)
            .frame(maxWidth: Theme.contentMaxWidth(1400), alignment: .leading)
        }
        .background(alignment: .top) {
            backdropHero
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationDestination(item: $streamTarget) { target in
            StreamPickerView(catalog: target.catalog, episode: target.episode)
        }
        .task { await hydrate() }
        .onAppear { AccentManager.shared.deriveAccent(from: item.posterURL ?? item.backdropURL) }
        .onDisappear { AccentManager.shared.reset() }
    }

    // MARK: - Backdrop hero

    @ViewBuilder
    private var backdropHero: some View {
        if let url = item.backdropURL {
            CachedAsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.clear
            }
            .frame(height: Theme.isCompact ? 320 : 560)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(
                // Vertical fade to the background, plus a subtle accent wash from the
                // artwork color along the leading edge for an Apple TV cinematic feel.
                ZStack {
                    LinearGradient(
                        colors: [
                            Theme.Colors.background.opacity(0.15),
                            Theme.Colors.background.opacity(0.7),
                            Theme.Colors.background
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                    LinearGradient(
                        colors: [accent.opacity(0.28), .clear],
                        startPoint: .bottomLeading, endPoint: .topTrailing
                    )
                    .blendMode(.plusLighter)
                }
            )
            .ignoresSafeArea(edges: .top)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.lg) {
            PosterImage(url: item.posterURL, width: Theme.scaled(280, min: 130), height: Theme.scaled(420, min: 195))

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(item.title)
                    .font(Theme.Font.screenTitle())
                    .screenTitleStyle()
                    .foregroundStyle(Theme.Colors.textPrimary)

                HStack(spacing: Theme.Spacing.md) {
                    if let year = item.year {
                        Text(String(year)).foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Text(item.contentID.type.displayName)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    if let rating = item.rating, rating > 0 {
                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                            .foregroundStyle(Theme.Colors.warning)
                    }
                }
                .font(.appFont(22))

                if let overview = item.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.appFont(22))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineSpacing(6)
                        .padding(.top, Theme.Spacing.sm)
                }

                if !item.isSeries {
                    FocusableButton(title: "Find Streams", systemImage: "play.fill", prominent: true) {
                        streamTarget = StreamTarget(catalog: item, episode: nil)
                    }
                    .frame(maxWidth: Theme.isCompact ? .infinity : 320)
                    .padding(.top, Theme.Spacing.md)
                }

                // Series: jump straight to the next unwatched episode.
                if item.isSeries, let nextUp = nextUnwatchedEpisode() {
                    FocusableButton(title: resumeButtonTitle(nextUp),
                                    systemImage: "play.fill", prominent: true) {
                        streamTarget = StreamTarget(catalog: item, episode: nextUp)
                    }
                    .frame(maxWidth: Theme.isCompact ? .infinity : 360)
                    .padding(.top, Theme.Spacing.md)
                }

                // Favorite this title (adds it to the library and marks it favorite).
                FocusableButton(title: isFavorited ? "Favorited" : "Add to Favorites",
                                systemImage: isFavorited ? "star.fill" : "star") {
                    toggleFavorite()
                }
                .frame(maxWidth: Theme.isCompact ? .infinity : 320)
                .padding(.top, Theme.Spacing.sm)

                if isHydrating {
                    ProgressView().tint(Theme.Colors.accent).padding(.top, Theme.Spacing.sm)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Favorites

    /// Whether this title is currently in the library as a favorite.
    private var isFavorited: Bool {
        _ = favoriteRefresh   // dependency so toggling re-evaluates
        let key = catalogAsMediaItem().contentKey
        return env.library.items.first(where: { $0.contentKey == key })?.isFavorite ?? false
    }

    private func toggleFavorite() {
        let probe = catalogAsMediaItem()
        if let existing = env.library.items.first(where: { $0.contentKey == probe.contentKey }) {
            env.library.toggleFavorite(existing)
        } else {
            // Not in the library yet: add it as a favorite.
            var item = probe
            item.isFavorite = true
            env.library.add(item)
        }
        favoriteRefresh.toggle()
    }

    /// A MediaItem standing in for this catalog title, used for library membership.
    /// It carries no playback URL (favoriting isn't playback); contentKey identifies it.
    private func catalogAsMediaItem() -> MediaItem {
        MediaItem(
            title: item.title,
            sourceType: item.isSeries ? .addon : .addon,
            playbackURL: URL(string: "frametv://catalog/\(item.contentID.stableKey)")!,
            posterURL: item.posterURL,
            backdropURL: item.backdropURL,
            legalAccessConfirmed: true,
            metadata: MediaMetadata(year: item.year),
            contentID: item.contentID,
            seriesTitle: item.isSeries ? item.title : nil
        )
    }

    /// First episode (in season/number order) that hasn't been watched yet. If the
    /// user is mid-episode somewhere, that in-progress episode is preferred.
    private func nextUnwatchedEpisode() -> EpisodeInfo? {
        let seasons = item.seasons
            .filter { $0.number > 0 }
            .sorted { $0.number < $1.number }
        let ordered = seasons.flatMap { $0.episodes.sorted { $0.number < $1.number } }
        // Prefer an in-progress episode.
        if let inProgress = ordered.first(where: {
            env.library.isEpisodeInProgress(imdb: item.contentID.imdb, tmdb: item.contentID.tmdb,
                                            season: $0.season, number: $0.number)
        }) { return inProgress }
        // Otherwise the first unwatched.
        return ordered.first(where: {
            !env.library.isEpisodeWatched(imdb: item.contentID.imdb, tmdb: item.contentID.tmdb,
                                          season: $0.season, number: $0.number)
        }) ?? ordered.first
    }

    private func resumeButtonTitle(_ ep: EpisodeInfo) -> String {
        let inProgress = env.library.isEpisodeInProgress(imdb: item.contentID.imdb, tmdb: item.contentID.tmdb,
                                                         season: ep.season, number: ep.number)
        return "\(inProgress ? "Resume" : "Play") \(ep.label)"
    }

    // MARK: - Movie

    private var movieBody: some View {
        EmptyView()
    }

    // MARK: - Series

    @ViewBuilder
    private var seriesBody: some View {
        if item.seasons.isEmpty {
            if !isHydrating {
                Text("No episode information available. Add a TMDB key in Settings for full series data.")
                    .font(.appFont(20))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        } else {
            // Season selector.
            let seasons = item.seasons.filter { $0.number > 0 }.isEmpty
                ? item.seasons : item.seasons.filter { $0.number > 0 }
            let activeSeason = selectedSeason ?? seasons.first?.number ?? 1

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach(seasons) { season in
                            seasonChip(season, isActive: season.number == activeSeason)
                        }
                    }
                }

                if let season = seasons.first(where: { $0.number == activeSeason }) {
                    ForEach(season.episodes) { ep in
                        episodeRow(ep)
                    }
                }
            }
        }
    }

    private func seasonChip(_ season: SeasonInfo, isActive: Bool) -> some View {
        Button { selectedSeason = season.number } label: {
            Text(season.displayName)
                .font(.appFont(20, weight: .semibold))
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(isActive ? Theme.Colors.accent : Theme.Colors.card,
                            in: Capsule())
                .foregroundStyle(isActive ? .white : Theme.Colors.textSecondary)
        }
        .buttonStyle(.plain)
    }

    private func episodeRow(_ ep: EpisodeInfo) -> some View {
        let watched = env.library.isEpisodeWatched(imdb: item.contentID.imdb, tmdb: item.contentID.tmdb,
                                               season: ep.season, number: ep.number)
        let inProgress = env.library.isEpisodeInProgress(imdb: item.contentID.imdb, tmdb: item.contentID.tmdb,
                                                     season: ep.season, number: ep.number)
        return Button { streamTarget = StreamTarget(catalog: item, episode: ep) } label: {
            HStack(spacing: Theme.Spacing.md) {
                PosterImage(url: ep.stillURL, width: Theme.scaled(200, min: 120), height: Theme.scaled(112, min: 68))
                    .opacity(watched ? 0.55 : 1)
                    .overlay(alignment: .bottomLeading) {
                        if watched {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.appFont(20))
                                .foregroundStyle(.white, Theme.Colors.accent)
                                .padding(6)
                        } else if inProgress {
                            Image(systemName: "play.circle.fill")
                                .font(.appFont(20))
                                .foregroundStyle(.white, Theme.Colors.accentSecondary)
                                .padding(6)
                        }
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(ep.label) · \(ep.displayTitle)")
                        .font(.appFont(22, weight: .semibold))
                        .foregroundStyle(watched ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                        .lineLimit(1)
                    // Runtime + air date line.
                    if let meta = episodeMetaLine(ep) {
                        Text(meta)
                            .font(.appFont(15))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    if let overview = ep.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.appFont(17))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Image(systemName: inProgress ? "play.circle" : "play.circle.fill")
                    .font(.appFont(30))
                    .foregroundStyle(Theme.Colors.accent)
            }
            .padding(.vertical, Theme.Spacing.xs)
            .contentShape(Rectangle())
        }
        .frameRowStyle()
    }

    /// Builds a "42 min · Aired Jan 3, 2024" style line from available episode data.
    private func episodeMetaLine(_ ep: EpisodeInfo) -> String? {
        var parts: [String] = []
        if let runtime = ep.runtime, runtime > 0 {
            let minutes = Int((runtime / 60).rounded())
            parts.append("\(minutes) min")
        }
        if let air = ep.airDate {
            let fmt = DateFormatter(); fmt.dateStyle = .medium
            parts.append("Aired \(fmt.string(from: air))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Hydration

    private func hydrate() async {
        guard item.contentID.imdb == nil || (item.isSeries && item.seasons.isEmpty) else { return }
        isHydrating = true
        let hydrated = await env.catalog.hydrate(item)
        item = hydrated
        if selectedSeason == nil {
            selectedSeason = hydrated.seasons.first(where: { $0.number > 0 })?.number
                ?? hydrated.seasons.first?.number
        }
        isHydrating = false
    }
}

// MARK: - Poster helper

/// A simple async poster/still image with a placeholder.
struct PosterImage: View {
    let url: URL?
    var width: CGFloat
    var height: CGFloat

    var body: some View {
        CachedAsyncImage(url: url) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            placeholder.shimmering()
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .fill(Theme.Colors.card)
            .overlay(
                Image(systemName: "film")
                    .font(.appFont(40))
                    .foregroundStyle(Theme.Colors.textTertiary)
            )
    }
}
