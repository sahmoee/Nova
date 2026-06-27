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
    @State private var item: CatalogItem
    @State private var isHydrating = false
    @State private var selectedSeason: Int?
    @State private var streamTarget: StreamTarget?

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
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationDestination(item: $streamTarget) { target in
            StreamPickerView(catalog: target.catalog, episode: target.episode)
        }
        .task { await hydrate() }
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

                if isHydrating {
                    ProgressView().tint(Theme.Colors.accent).padding(.top, Theme.Spacing.sm)
                }
            }
            Spacer(minLength: 0)
        }
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
        Button { streamTarget = StreamTarget(catalog: item, episode: ep) } label: {
            HStack(spacing: Theme.Spacing.md) {
                PosterImage(url: ep.stillURL, width: Theme.scaled(200, min: 120), height: Theme.scaled(112, min: 68))

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(ep.label) · \(ep.displayTitle)")
                        .font(.appFont(22, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    if let overview = ep.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.appFont(17))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Image(systemName: "play.circle.fill")
                    .font(.appFont(30))
                    .foregroundStyle(Theme.Colors.accent)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
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
