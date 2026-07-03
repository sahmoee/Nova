//
//  ContentDetailView.swift
//  FrameTV
//
//  Detail screen for a catalog item. For movies it shows artwork, overview, and a
//  "Find Streams" action. For series it hydrates seasons/episodes and lists them,
//  with each episode routing into the stream picker.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

struct ContentDetailView: View {
    let initialItem: CatalogItem

    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dynamicAccent) private var accent
    @State private var item: CatalogItem
    @State private var isHydrating = false
    @State private var selectedSeason: Int?
    @State private var streamTarget: StreamTarget?
    @State private var favoriteRefresh = false   // toggles to re-read favorite state
    @State private var trailerURL: URL?          // fetched from TMDB if available
    @State private var ratings = ExternalRatings()   // IMDb/RT/Metacritic from OMDb
    @State private var showCollectionPicker = false
    @State private var newCollectionName = ""
    @State private var cast: [CastMember] = []
    @State private var related: [CatalogItem] = []

    init(item: CatalogItem) {
        self.initialItem = item
        _item = State(initialValue: item)
    }

    /// Identifies what the stream picker should look for. `forceManual` makes the
    /// picker show the list even when auto-select is enabled (for "Choose Stream").
    struct StreamTarget: Identifiable, Hashable {
        let id = UUID()
        let catalog: CatalogItem
        let episode: EpisodeInfo?
        var forceManual: Bool = false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                heroHeader
                    .frame(maxWidth: .infinity)

                if item.isSeries {
                    seriesBody
                }

                if trailerURL != nil {
                    trailersSection
                }

                if !related.isEmpty {
                    relatedSection
                }

                if !cast.isEmpty {
                    castSection
                }

                if isHydrating {
                    ProgressView().tint(Theme.Colors.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.lg)
                }
            }
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.Colors.appBackground.ignoresSafeArea())
        .navigationDestination(item: $streamTarget) { target in
            StreamPickerView(catalog: target.catalog, episode: target.episode,
                             forceManual: target.forceManual)
        }
        .task { await hydrate() }
        .task { await fetchTrailer() }
        .task { await fetchExtras() }
        .task(id: item.contentID.imdb) { await fetchRatings() }
        .sheet(isPresented: $showCollectionPicker) {
            collectionPickerSheet
        }
        .onAppear { AccentManager.shared.deriveAccent(from: item.posterURL ?? item.backdropURL) }
        .onDisappear { AccentManager.shared.reset() }
    }

    // MARK: - Hero header (centered, Apple TV style)

    /// The backdrop height, sized to the device so it scales across iPhone sizes and
    /// iPad instead of being a fixed number. About 48% of screen height on iOS,
    /// clamped to a comfortable range; a larger fixed value on tvOS.
    private var heroHeight: CGFloat {
        #if os(iOS)
        let h = UIScreen.main.bounds.height
        if Theme.isPad {
            return min(max(h * 0.42, 460), 760)
        }
        return min(max(h * 0.38, 300), 520)
        #else
        return 560
        #endif
    }

    private var heroHeader: some View {
        VStack(alignment: .center, spacing: Theme.Spacing.sm) {
            // Backdrop with a fade to the background at the bottom. Kept in the normal
            // scroll flow (no safe-area escape) so the content below follows directly
            // with no gap.
            CachedAsyncImage(url: item.backdropURL ?? item.posterURL, maxPixel: 1600) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(Theme.Colors.card).shimmering()
            }
            .frame(height: heroHeight)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(
                LinearGradient(
                    colors: [.clear, .clear, Theme.Colors.background.opacity(0.7), Theme.Colors.background],
                    startPoint: .top, endPoint: .bottom
                )
            )

            // Type / genre line.
            Text(metaLine)
                .font(.appFont(18, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            // Primary Play + circular watched toggle.
            HStack(spacing: Theme.Spacing.md) {
                Button {
                    if item.isSeries, let first = firstEpisode() {
                        streamTarget = StreamTarget(catalog: item, episode: first)
                    } else {
                        streamTarget = StreamTarget(catalog: item, episode: nil)
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "play.fill")
                        Text(item.isSeries ? "Play First Episode" : playButtonTitle)
                    }
                    .font(.appFont(20, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.vertical, Theme.Spacing.md)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .background(Capsule().fill(.white))
                }
                .buttonStyle(FrameChipButtonStyle())
                .contextMenu {
                    Button {
                        streamTarget = StreamTarget(catalog: item, episode: nil, forceManual: true)
                    } label: { Label("Choose Stream…", systemImage: "list.bullet") }
                }

                Button { toggleWatched() } label: {
                    Image(systemName: isWatched ? "checkmark.circle.fill" : "checkmark")
                        .font(.appFont(24, weight: .semibold))
                        .foregroundStyle(isWatched ? .black : .white)
                        .frame(width: 58, height: 58)
                        .background(Circle().fill(isWatched ? .white : Color.white.opacity(0.16)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(FrameChipButtonStyle())
            }

            // Overview + year.
            if let overview = item.overview, !overview.isEmpty {
                Text(overview)
                    .font(.appFont(17))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Spacing.edge)
            }
            if let year = item.year {
                Text(String(year))
                    .font(.appFont(15))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }

            // Secondary actions (Favorite / Collection / Trailer / links).
            secondaryActionsRail
                .padding(.top, Theme.Spacing.xs)
        }
        .frame(maxWidth: .infinity)
    }

    /// "TV Show · Comedy · Animation" style line.
    private var metaLine: String {
        var parts: [String] = [item.contentID.type == .series ? "TV Show" : "Movie"]
        parts.append(contentsOf: item.genres.prefix(2))
        return parts.joined(separator: " · ")
    }

    private func firstEpisode() -> EpisodeInfo? {
        let seasons = item.seasons.filter { $0.number > 0 }.isEmpty
            ? item.seasons : item.seasons.filter { $0.number > 0 }
        return seasons.sorted { $0.number < $1.number }
            .first?.episodes.sorted { $0.number < $1.number }.first
    }

    // MARK: - Trailers / Related / Cast

    private var trailersSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("Trailers")
            if let trailer = trailerURL {
                Button {
                    #if os(iOS)
                    UIApplication.shared.open(trailer)
                    #endif
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .fill(Theme.Colors.card)
                        Image(systemName: "play.circle.fill")
                            .font(.appFont(44))
                            .foregroundStyle(.white.opacity(0.9))
                        VStack {
                            Spacer()
                            HStack {
                                Image(systemName: "play.fill").font(.appFont(14))
                                Text("\(item.title) — Trailer")
                                    .font(.appFont(15, weight: .medium)).lineLimit(1)
                                Spacer()
                            }
                            .foregroundStyle(.white)
                            .padding(Theme.Spacing.sm)
                        }
                    }
                    .frame(width: Theme.scaled(320, min: 280), height: Theme.scaled(180, min: 158))
                    .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                }
                .buttonStyle(FrameListRowStyle())
                .padding(.horizontal, Theme.Spacing.edge)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("Related", chevron: true)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.md) {
                    ForEach(related) { rel in
                        NavigationLink {
                            ContentDetailView(item: rel)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                PosterImage(url: rel.posterURL,
                                            width: Theme.scaled(150, min: 120),
                                            height: Theme.scaled(225, min: 180))
                                Text(rel.title)
                                    .font(.appFont(15, weight: .medium))
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                    .lineLimit(1)
                                    .frame(width: Theme.scaled(150, min: 120), alignment: .leading)
                            }
                        }
                        .buttonStyle(FrameListRowStyle())
                    }
                }
                .padding(.horizontal, Theme.Spacing.edge)
                .padding(.vertical, Theme.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var castSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionHeader("Cast")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.md) {
                    ForEach(cast) { member in
                        VStack(spacing: 6) {
                            CachedAsyncImage(url: member.profileURL, maxPixel: 300) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Circle().fill(Theme.Colors.card)
                                    .overlay(Image(systemName: "person.fill")
                                        .font(.appFont(28)).foregroundStyle(Theme.Colors.textTertiary))
                            }
                            .frame(width: Theme.scaled(88, min: 72), height: Theme.scaled(88, min: 72))
                            .clipShape(Circle())
                            Text(member.name)
                                .font(.appFont(14, weight: .medium))
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .lineLimit(1)
                            if let character = member.character, !character.isEmpty {
                                Text(character)
                                    .font(.appFont(12))
                                    .foregroundStyle(Theme.Colors.textTertiary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: Theme.scaled(100, min: 84))
                    }
                }
                .padding(.horizontal, Theme.Spacing.edge)
                .padding(.vertical, Theme.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionHeader(_ title: String, chevron: Bool = false) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.appFont(24, weight: .bold))
                .foregroundStyle(Theme.Colors.textPrimary)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.appFont(18, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(.horizontal, Theme.Spacing.edge)
    }

    private func fetchExtras() async {
        guard let tmdb = item.contentID.tmdb, env.tmdb.hasKey else { return }
        let isMovie = item.contentID.type == .movie
        async let castResult = try? env.tmdb.cast(tmdbID: tmdb, isMovie: isMovie)
        async let relatedResult = try? env.tmdb.related(tmdbID: tmdb, isMovie: isMovie)
        let (c, r) = await (castResult, relatedResult)
        if let c { cast = c }
        if let r { related = Array(r.prefix(20)) }
    }

    // MARK: - Backdrop hero

    @ViewBuilder
    private var backdropHero: some View {
        if let url = item.backdropURL {
            CachedAsyncImage(url: url, maxPixel: 1600) { image in
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
            PosterImage(url: item.posterURL, width: Theme.scaled(280, min: 120), height: Theme.scaled(420, min: 180))

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(item.title)
                    .font(Theme.Font.screenTitle())
                    .screenTitleStyle()
                    .foregroundStyle(Theme.Colors.textPrimary)

                WrapFlowLayout(spacing: Theme.Spacing.md, lineSpacing: Theme.Spacing.xs) {
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

                // External ratings (IMDb / Rotten Tomatoes / Metacritic) from OMDb.
                if !ratings.isEmpty {
                    WrapFlowLayout(spacing: Theme.Spacing.sm, lineSpacing: Theme.Spacing.sm) {
                        if let imdb = ratings.imdb {
                            ratingBadge(text: String(format: "%.1f", imdb), label: "IMDb",
                                        color: Color(red: 0.96, green: 0.77, blue: 0.13))
                        }
                        if let rt = ratings.rottenTomatoes {
                            ratingBadge(text: "\(rt)%", label: "RT",
                                        color: rt >= 60 ? Theme.Colors.error : Theme.Colors.success)
                        }
                        if let mc = ratings.metacritic {
                            ratingBadge(text: "\(mc)", label: "MC",
                                        color: mc >= 60 ? Theme.Colors.success : Theme.Colors.warning)
                        }
                    }
                    .padding(.top, Theme.Spacing.xs)
                }

                // Open this title on external sites.
                sourceLinks
                    .padding(.top, Theme.Spacing.xs)

                if let overview = item.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.appFont(19))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineSpacing(5)
                        .padding(.top, Theme.Spacing.sm)
                }

                if !item.isSeries {
                    // Primary action: full-width Play / Find Streams. For movies the
                    // stream picker auto-loads and auto-selects the best stream, so
                    // this goes straight to playback when auto-select is on.
                    FocusableButton(title: playButtonTitle, systemImage: "play.fill", prominent: true) {
                        streamTarget = StreamTarget(catalog: item, episode: nil)
                    }
                    .contextMenu {
                        Button {
                            streamTarget = StreamTarget(catalog: item, episode: nil, forceManual: true)
                        } label: { Label("Choose Stream…", systemImage: "list.bullet") }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, Theme.Spacing.md)
                }

                if item.isSeries, let nextUp = nextUnwatchedEpisode() {
                    FocusableButton(title: resumeButtonTitle(nextUp),
                                    systemImage: "play.fill", prominent: true) {
                        streamTarget = StreamTarget(catalog: item, episode: nextUp)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, Theme.Spacing.md)
                }

                // Secondary actions: a compact, evenly-sized rail that scrolls, so the
                // buttons are consistent and aligned instead of a tall stack.
                secondaryActionsRail
                    .padding(.top, Theme.Spacing.sm)

                if isHydrating {
                    ProgressView().tint(Theme.Colors.accent).padding(.top, Theme.Spacing.sm)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Secondary actions

    /// A compact horizontal rail of consistent, evenly-sized secondary actions, so
    /// they read as one aligned group instead of a tall stack of full-width buttons.
    private var secondaryActionsRail: some View {
        WrapFlowLayout(spacing: Theme.Spacing.sm, lineSpacing: Theme.Spacing.sm, alignment: .center) {
            if !item.isSeries {
                detailAction("Choose Stream", systemImage: "list.bullet") {
                    streamTarget = StreamTarget(catalog: item, episode: nil, forceManual: true)
                }
            }
            #if os(iOS)
            if let trailer = trailerURL {
                detailAction("Trailer", systemImage: "film") {
                    UIApplication.shared.open(trailer)
                }
            }
            #endif
            detailAction(isFavorited ? "Favorited" : "Favorite",
                         systemImage: isFavorited ? "star.fill" : "star",
                         active: isFavorited) {
                toggleFavorite()
            }
            detailAction("Collection", systemImage: "rectangle.stack.badge.plus") {
                showCollectionPicker = true
            }
            if item.contentID.type == .movie {
                detailAction(isWatched ? "Watched" : "Mark Watched",
                             systemImage: isWatched ? "checkmark.circle.fill" : "checkmark.circle",
                             active: isWatched) {
                    toggleWatched()
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.edge)
        .padding(.vertical, Theme.Spacing.xs)
        .frame(maxWidth: .infinity)
    }

    /// One compact secondary action: icon over a short label in a fixed-width pill.
    private func detailAction(_ title: String, systemImage: String,
                              active: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.appFont(22, weight: .semibold))
                Text(title)
                    .font(.appFont(14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(active ? accent : Theme.Colors.textPrimary)
            .frame(width: Theme.scaled(96, min: 84), height: Theme.scaled(84, min: 74))
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.Colors.cardGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(active ? accent.opacity(0.6) : Color.white.opacity(0.07), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(FrameListRowStyle())
    }

    // MARK: - Collection picker

    @ViewBuilder
    private var collectionPickerSheet: some View {
        NavigationStack {
            List {
                if env.library.collections.isEmpty {
                    Text("No collections yet. Create one below.")
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                ForEach(env.library.collections) { collection in
                    let probe = catalogAsMediaItem()
                    let inIt = env.library.isInCollection(collection.id, item: probe)
                    Button {
                        if inIt {
                            env.library.removeFromCollection(collection.id, contentKey: probe.contentKey)
                        } else {
                            env.library.addToCollection(collection.id, item: probe)
                            // Ensure the item exists in the library so it resolves later.
                            if !env.library.items.contains(where: { $0.contentKey == probe.contentKey }) {
                                env.library.add(probe)
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: collection.systemImage)
                            Text(collection.name)
                            Spacer()
                            if inIt { Image(systemName: "checkmark").foregroundStyle(Theme.Colors.accent) }
                        }
                    }
                }
                Section("New Collection") {
                    HStack {
                        TextField("Name", text: $newCollectionName)
                        Button("Create") {
                            let trimmed = newCollectionName.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty else { return }
                            let c = env.library.createCollection(name: trimmed)
                            env.library.addToCollection(c.id, item: catalogAsMediaItem())
                            newCollectionName = ""
                        }
                        .disabled(newCollectionName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle("Add to Collection")
            .toolbar {
                Button("Done") { showCollectionPicker = false }
            }
        }
    }

    // MARK: - Favorites

    /// Whether this title is currently in the library as a favorite.
    private var isFavorited: Bool {
        _ = favoriteRefresh   // dependency so toggling re-evaluates
        let key = catalogAsMediaItem().contentKey
        return env.library.items.first(where: { $0.contentKey == key })?.isFavorite ?? false
    }

    /// Whether this title has been fully watched.
    private var isWatched: Bool {
        _ = favoriteRefresh
        let key = catalogAsMediaItem().contentKey
        return env.library.items.first(where: { $0.contentKey == key })?.isWatched ?? false
    }

    private func toggleWatched() {
        let probe = catalogAsMediaItem()
        if let existing = env.library.items.first(where: { $0.contentKey == probe.contentKey }) {
            if existing.isWatched { env.library.markUnwatched(existing) }
            else { env.library.markWatched(existing) }
        } else {
            var item = probe
            env.library.add(item)
            if let added = env.library.items.first(where: { $0.contentKey == item.contentKey }) {
                env.library.markWatched(added)
            }
        }
        favoriteRefresh.toggle()
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

    /// The primary movie button reads "Play" when auto-select is on (it goes straight
    /// to playback), or "Find Streams" when the user picks manually by default.
    private var playButtonTitle: String {
        env.settings.autoSelectStream ? "Play" : "Find Streams"
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
                Text(env.tmdb.hasKey
                     ? "Couldn't load episodes for this title. It may not have episode data on TMDB, or the lookup failed — pull to refresh to try again."
                     : "No episode information available. Add a TMDB key in Settings for full series data.")
                    .font(.appFont(20))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        } else {
            // Season selector.
            let seasons = item.seasons.filter { $0.number > 0 }.isEmpty
                ? item.seasons : item.seasons.filter { $0.number > 0 }
            let activeSeason = selectedSeason ?? seasons.first?.number ?? 1

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                // Season picker as a menu (tap to choose), matching the reference's
                // "Season 1 ⌄" control.
                Menu {
                    ForEach(seasons) { season in
                        Button {
                            selectedSeason = season.number
                        } label: {
                            if season.number == activeSeason {
                                Label(season.displayName, systemImage: "checkmark")
                            } else {
                                Text(season.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(seasons.first(where: { $0.number == activeSeason })?.displayName ?? "Season \(activeSeason)")
                            .font(.appFont(28, weight: .bold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.appFont(18, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .padding(.horizontal, Theme.Spacing.edge)

                // Episode rail: wide 16:9 cards with the episode info overlaid on the
                // still (title, number, synopsis), matching the reference.
                if let season = seasons.first(where: { $0.number == activeSeason }) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: Theme.Spacing.md) {
                            ForEach(season.episodes) { ep in
                                episodeCard(ep)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.edge)
                        .padding(.vertical, Theme.Spacing.xs)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func seasonChip(_ season: SeasonInfo, isActive: Bool) -> some View {
        Button { selectedSeason = season.number } label: {
            Text(season.displayName)
                .font(.appFont(20, weight: .semibold))
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background {
                    if isActive {
                        Capsule().fill(
                            LinearGradient(colors: [Theme.Colors.accent, Theme.Colors.accent.opacity(0.8)],
                                           startPoint: .top, endPoint: .bottom)
                        )
                    } else {
                        Capsule().fill(Theme.Colors.card)
                    }
                }
                .foregroundStyle(isActive ? .white : Theme.Colors.textSecondary)
                .contentShape(Capsule())
        }
        .buttonStyle(FrameChipButtonStyle())
    }

    /// A wide episode card: the still fills it with the episode number, title, and
    /// synopsis overlaid on a gradient at the bottom, matching the reference layout.
    private func episodeCard(_ ep: EpisodeInfo) -> some View {
        let watched = env.library.isEpisodeWatched(imdb: item.contentID.imdb, tmdb: item.contentID.tmdb,
                                                   season: ep.season, number: ep.number)
        let inProgress = env.library.isEpisodeInProgress(imdb: item.contentID.imdb, tmdb: item.contentID.tmdb,
                                                         season: ep.season, number: ep.number)
        let cardWidth = Theme.scaled(330, min: 280)
        return Button { streamTarget = StreamTarget(catalog: item, episode: ep) } label: {
            ZStack(alignment: .bottomLeading) {
                CachedAsyncImage(url: ep.stillURL ?? item.backdropURL ?? item.posterURL, maxPixel: 780) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Theme.Colors.card).shimmering()
                }
                .frame(width: cardWidth, height: cardWidth * 9.0 / 16.0 + 120)
                .clipped()

                LinearGradient(colors: [.clear, .black.opacity(0.55), .black.opacity(0.92)],
                               startPoint: .center, endPoint: .bottom)

                VStack(alignment: .leading, spacing: 4) {
                    Text("EPISODE \(ep.number)")
                        .font(.appFont(13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(ep.displayTitle)
                        .font(.appFont(19, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let overview = ep.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.appFont(15))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    HStack {
                        Image(systemName: inProgress ? "play.circle" : "play.fill")
                            .font(.appFont(18))
                            .foregroundStyle(.white)
                        Spacer()
                        Menu {
                            Button {
                                _ = env.library.setEpisodeWatched(!watched,
                                                                  imdb: item.contentID.imdb,
                                                                  tmdb: item.contentID.tmdb,
                                                                  season: ep.season, number: ep.number)
                                favoriteRefresh.toggle()
                            } label: {
                                Label(watched ? "Mark as Unwatched" : "Mark as Watched",
                                      systemImage: watched ? "checkmark.circle.badge.xmark" : "checkmark.circle")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.appFont(18, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.top, 2)
                }
                .padding(Theme.Spacing.md)

                if watched {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.appFont(22))
                        .foregroundStyle(.white, Theme.Colors.accent)
                        .padding(Theme.Spacing.sm)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .frame(width: cardWidth)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(FrameListRowStyle())
    }

    private func episodeRow(_ ep: EpisodeInfo) -> some View {
        let watched = env.library.isEpisodeWatched(imdb: item.contentID.imdb, tmdb: item.contentID.tmdb,
                                               season: ep.season, number: ep.number)
        let inProgress = env.library.isEpisodeInProgress(imdb: item.contentID.imdb, tmdb: item.contentID.tmdb,
                                                     season: ep.season, number: ep.number)
        return Button { streamTarget = StreamTarget(catalog: item, episode: ep) } label: {
            HStack(spacing: Theme.Spacing.md) {
                // Episode still art in proper 16:9 shape (falls back to the show poster
                // cropped to 16:9 when a still isn't available), so nothing stretches.
                EpisodeStill(stillURL: ep.stillURL, fallbackURL: item.backdropURL ?? item.posterURL,
                             width: Theme.scaled(150, min: 116))
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
        .contextMenu {
            // Long-press an episode to flip its watched state. Episodes that have
            // never been played aren't in the library yet and can't be marked.
            Button {
                _ = env.library.setEpisodeWatched(!watched,
                                                  imdb: item.contentID.imdb,
                                                  tmdb: item.contentID.tmdb,
                                                  season: ep.season, number: ep.number)
                favoriteRefresh.toggle()
            } label: {
                Label(watched ? "Mark as Unwatched" : "Mark as Watched",
                      systemImage: watched ? "checkmark.circle.badge.xmark" : "checkmark.circle")
            }
        }
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

    /// Looks up a trailer URL from TMDB when the item has a TMDB id. Best-effort;
    /// failures leave the button hidden.
    private func fetchTrailer() async {
        guard env.tmdb.hasKey, let tmdb = item.contentID.tmdb else { return }
        let isMovie = item.contentID.type == .movie
        if let url = try? await env.tmdb.trailerURL(tmdbID: tmdb, isMovie: isMovie) {
            trailerURL = url
        }
    }

    /// Loads IMDb / Rotten Tomatoes / Metacritic scores from OMDb (needs the IMDb id,
    /// which hydration fills in). No-op without an OMDb key.
    private func fetchRatings() async {
        guard env.omdb.hasKey, let imdb = item.contentID.imdb else { return }
        let r = await env.omdb.ratings(forIMDB: imdb)
        if !r.isEmpty { ratings = r }
    }

    private func ratingBadge(text: String, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.appFont(13, weight: .bold))
                .foregroundStyle(color)
            Text(text)
                .font(.appFont(16, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Theme.Colors.card)
        )
        .overlay(
            Capsule().strokeBorder(color.opacity(0.4), lineWidth: 1)
        )
    }

    /// Buttons to open this title on external sites. IMDb and Rotten Tomatoes have no
    /// public API, so these are search/deep links rather than embedded data.
    @ViewBuilder private var sourceLinks: some View {
        let title = item.title
        let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
        let isMovie = item.contentID.type == .movie
        WrapFlowLayout(spacing: Theme.Spacing.sm, lineSpacing: Theme.Spacing.sm) {
            if let imdb = item.contentID.imdb,
               let url = URL(string: "https://www.imdb.com/title/\(imdb)/") {
                sourceLinkButton("IMDb", url: url)
            } else if let url = URL(string: "https://www.imdb.com/find/?q=\(encoded)") {
                sourceLinkButton("IMDb", url: url)
            }
            if let url = URL(string: "https://www.rottentomatoes.com/search?search=\(encoded)") {
                sourceLinkButton("RT", url: url)
            }
            if let tmdb = item.contentID.tmdb,
               let url = URL(string: "https://www.themoviedb.org/\(isMovie ? "movie" : "tv")/\(tmdb)") {
                sourceLinkButton("TMDB", url: url)
            }
        }
    }

    private func sourceLinkButton(_ label: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.right.square")
                Text(label).lineLimit(1)
            }
            .font(.appFont(15, weight: .medium))
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(Theme.Colors.accent)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 8)
            .background(Capsule().fill(Theme.Colors.card))
        }
        .buttonStyle(.plain)
    }

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
/// A 16:9 episode thumbnail using the episode still (or a show-art fallback), sized to
/// a fixed width and cropped to fill so it never stretches.
struct EpisodeStill: View {
    let stillURL: URL?
    let fallbackURL: URL?
    var width: CGFloat

    private var height: CGFloat { width * 9.0 / 16.0 }

    var body: some View {
        CachedAsyncImage(url: stillURL ?? fallbackURL, maxPixel: 780) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colors.card)
                .overlay(
                    Image(systemName: "play.tv")
                        .font(.appFont(28))
                        .foregroundStyle(Theme.Colors.textTertiary)
                )
                .shimmering()
        }
        .frame(width: width, height: height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct PosterImage: View {
    let url: URL?
    var width: CGFloat
    var height: CGFloat

    var body: some View {
        CachedAsyncImage(url: url, maxPixel: 900) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            placeholder.shimmering()
        }
        .frame(width: width, height: height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .accessibilityHidden(true)
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
