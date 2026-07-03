//
//  HomeView.swift
//  FrameTV
//
//  Apple TV-style dashboard: hero header, Continue Watching, Recently Added,
//  Recently Added, and Favorites.
//

import SwiftUI

struct HomeView: View {
    @Binding var path: NavigationPath
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var nav: NavigationCoordinator
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var shelfStore = HomeShelfStore.shared
    @State private var selectedItem: MediaItem?
    @State private var showCustomize = false
    @State private var heroIndex = 0
    @State private var showQueue = false

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.Colors.appBackground.ignoresSafeArea()

                if library.items.isEmpty && shelfStore.enabledShelves.isEmpty {
                    EmptyStateView(
                        systemImage: "play.tv",
                        title: "Welcome to FrameTV",
                        message: "Add a source or a direct link in Settings to start building your library.",
                        actionTitle: "Set Up Sources",
                        action: { nav.selection = .settings }
                    )
                } else {
                    switch settings.homeStyle {
                    case .cinematic: cinematicContent
                    case .classic:   classicContent
                    }
                }
            }
            .navigationDestination(item: $selectedItem) { item in
                PlayerView(item: item)
            }
            .navigationDestination(for: CatalogItem.self) { item in
                ContentDetailView(item: item)
            }
            .sheet(isPresented: $showCustomize) {
                HomeCustomizeView()
            }
            .sheet(isPresented: $showQueue) {
                QueueManageView()
            }
        }
    }

    // MARK: - Classic layout (original dashboard)

    private var classicContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.rowGap) {
                if !env.tmdb.hasKey {
                    setupBanner
                }
                if let hero = featuredItem {
                    FeaturedHero(item: hero) { play($0) }
                        .overlay(alignment: .topTrailing) { customizeButton }
                        .overlay(alignment: .topLeading) { brandMark }
                } else {
                    header
                }
                if !library.continueWatching.isEmpty {
                    continueWatchingRow
                }
                if !library.queuedItems.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("Up Next in Queue")
                                .font(Theme.Font.sectionTitle())
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Spacer()
                            Button("Manage") { showQueue = true }
                                .font(.appFont(17, weight: .semibold))
                                .foregroundStyle(Theme.Colors.accent)
                                .buttonStyle(FrameChipButtonStyle())
                        }
                        .padding(.horizontal, Theme.Spacing.edge)
                        MediaRow(title: "",
                                 items: Array(library.queuedItems.prefix(20))) { play($0) }
                    }
                }

                ForEach(shelfStore.enabledShelves) { shelf in
                    CatalogShelfRow(shelf: shelf)
                }
                if !library.recentlyAdded.isEmpty {
                    MediaRow(title: "Recently Added",
                             items: library.recentlyAdded) { play($0) }
                }
                if !library.favorites.isEmpty {
                    MediaRow(title: "Favorites",
                             items: library.favorites) { play($0) }
                }
            }
            .padding(.bottom, Theme.Spacing.lg)
        }
        #if os(tvOS)
        .ignoresSafeArea(edges: featuredItem != nil ? .top : [])
        #endif
    }

    // MARK: - Cinematic layout (new default)

    /// The set of items to rotate through the top hero carousel.
    private var heroItems: [MediaItem] {
        var seen = Set<UUID>()
        let pool = library.continueWatching + library.recentlyAdded + library.favorites
        return pool.filter { seen.insert($0.id).inserted }.prefix(8).map { $0 }
    }

    private var cinematicContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.rowGap) {
                if !env.tmdb.hasKey {
                    setupBanner
                }

                heroCarousel

                if !library.continueWatching.isEmpty {
                    continueWatchingRow
                }

                if !library.queuedItems.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("Up Next in Queue")
                                .font(Theme.Font.sectionTitle())
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Spacer()
                            Button("Manage") { showQueue = true }
                                .font(.appFont(17, weight: .semibold))
                                .foregroundStyle(Theme.Colors.accent)
                                .buttonStyle(FrameChipButtonStyle())
                        }
                        .padding(.horizontal, Theme.Spacing.edge)
                        MediaRow(title: "",
                                 items: Array(library.queuedItems.prefix(20))) { play($0) }
                    }
                }


                discoverSection

                ForEach(shelfStore.enabledShelves) { shelf in
                    CatalogShelfRow(shelf: shelf)
                }
                if !library.recentlyAdded.isEmpty {
                    MediaRow(title: "Recently Added",
                             items: library.recentlyAdded) { play($0) }
                }
                if !library.favorites.isEmpty {
                    MediaRow(title: "Favorites",
                             items: library.favorites) { play($0) }
                }
            }
            .padding(.bottom, Theme.Spacing.lg)
        }
        #if os(tvOS)
        .ignoresSafeArea(edges: .top)
        #endif
    }

    /// A full-bleed, swipeable hero carousel with page dots — the centerpiece of the
    /// cinematic home. Falls back to the plain header when there's nothing to show.
    @ViewBuilder
    private var heroCarousel: some View {
        let items = heroItems
        if items.isEmpty {
            header
        } else {
            VStack(spacing: Theme.Spacing.sm) {
                TabView(selection: $heroIndex) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        FeaturedHero(item: item) { play($0) }
                            .overlay(alignment: .topTrailing) { customizeButton }
                            .overlay(alignment: .topLeading) { brandMark }
                            .tag(idx)
                    }
                }
                #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: Theme.isCompact ? 300 : 440)
                #else
                .tabViewStyle(.automatic)
                .frame(height: 620)
                #endif

                // Page dots.
                if items.count > 1 {
                    HStack(spacing: 7) {
                        ForEach(items.indices, id: \.self) { i in
                            Circle()
                                .fill(i == heroIndex ? Color.white : Color.white.opacity(0.4))
                                .frame(width: i == heroIndex ? 9 : 6,
                                       height: i == heroIndex ? 9 : 6)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .animation(.easeInOut(duration: 0.2), value: heroIndex)
                }
            }
        }
    }

    /// The "Discover" section: large painterly gradient tiles linking to Watchlist,
    /// Trending, and other catalog destinations, echoing a streaming-app home.
    private var discoverSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Discover")
                .font(Theme.Font.sectionTitle())
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal, Theme.Spacing.edge)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.lg) {
                    ForEach(DiscoverTile.all) { tile in
                        Button { openDiscover(tile) } label: {
                            discoverTileCard(tile)
                        }
                        .frameRowStyle()
                    }
                }
                .padding(.horizontal, Theme.Spacing.edge)
            }
        }
    }

    private func discoverTileCard(_ tile: DiscoverTile) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Painterly-style gradient background (an approximation of a textured
            // tile — not a copyrighted image), with layered highlights and a
            // vignette for depth.
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(
                    LinearGradient(colors: tile.colors,
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(
                            RadialGradient(colors: [.white.opacity(0.16), .clear],
                                           center: .topLeading, startRadius: 4, endRadius: 220)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(
                            LinearGradient(colors: [.clear, .black.opacity(0.35)],
                                           startPoint: .center, endPoint: .bottom)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )

            // Prominent tile icon: a clear glyph in a soft translucent circle at the
            // top-left, plus the faint oversized glyph kept for background texture.
            VStack {
                HStack {
                    Image(systemName: tile.systemImage)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(.white.opacity(0.16), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                        .padding(Theme.Spacing.md)
                    Spacer()
                }
                Spacer()
            }

            // Faint oversized glyph in the corner for texture.
            Image(systemName: tile.systemImage)
                .font(.system(size: 90, weight: .bold))
                .foregroundStyle(.white.opacity(0.08))
                .offset(x: 12, y: 20)

            Text(tile.title)
                .font(.appFont(26, weight: .heavy))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
                .padding(Theme.Spacing.md)
                .multilineTextAlignment(.leading)
        }
        .frame(width: Theme.isCompact ? 300 : 360,
               height: Theme.isCompact ? 170 : 200)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func openDiscover(_ tile: DiscoverTile) {
        switch tile.destination {
        case .discover: nav.selection = .discover
        case .library:  nav.selection = .library
        case .settings: nav.selection = .settings
        }
    }

    // MARK: - Featured hero selection

    /// The item to spotlight at the top: prefer the most recent Continue Watching,
    /// then the newest Recently Added, then the first favorite.
    private var featuredItem: MediaItem? {
        library.continueWatching.first
            ?? library.recentlyAdded.first
            ?? library.favorites.first
    }

    private var brandMark: some View {
        // A larger, more elegant wordmark: serif design, tight tracking, and a soft
        // white-to-silver vertical sheen so it reads like a title card over artwork.
        Text("FrameTV")
            .font(.system(size: Theme.dynamicFontSize(40), weight: .bold, design: .serif))
            .kerning(0.5)
            .foregroundStyle(
                LinearGradient(colors: [.white, .white.opacity(0.75)],
                               startPoint: .top, endPoint: .bottom)
            )
            .shadow(color: .black.opacity(0.6), radius: 8, y: 2)
            .padding(.horizontal, Theme.Spacing.edge)
            .padding(.top, Theme.Spacing.sm)
            #if os(tvOS)
            .safeAreaPadding(.top)
            .safeAreaPadding(.leading)
            #endif
    }

    private var customizeButton: some View {
        Button {
            showCustomize = true
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.appFont(22, weight: .semibold))
                .foregroundStyle(.white)
                .padding(Theme.Spacing.sm)
                .background(.ultraThinMaterial, in: Circle())
        }
        .frameIconStyle()
        .padding(.horizontal, Theme.Spacing.edge)
        .padding(.top, Theme.Spacing.sm)
        #if os(tvOS)
        .safeAreaPadding(.top)
        .safeAreaPadding(.trailing)
        #endif
    }

    // MARK: - Fallback header (no content yet)

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("FrameTV")
                    .font(Theme.Font.screenTitle())
                    .screenTitleStyle()
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Your personal media hub")
                    .font(.appFont(24))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            Button {
                showCustomize = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.appFont(22, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.sm)
                    .background(Theme.Colors.card, in: Circle())
            }
            .frameIconStyle()
        }
        .padding(.horizontal, Theme.Spacing.edge)
        .padding(.top, Theme.Spacing.lg)
    }

    // MARK: - Actions

    private func play(_ item: MediaItem) {
        selectedItem = item
    }

    /// Restarts an item from the beginning: clears its saved progress, then plays.
    private func restart(_ item: MediaItem) {
        library.clearProgress(for: item.id)
        var fresh = item
        fresh.lastPlayedPosition = 0
        selectedItem = fresh
    }

    /// Shown when the movie database key is missing (nothing loads without it). Taps
    /// through to Settings, where the setup checklist lives.
    private var setupBanner: some View {
        Button {
            nav.selection = .settings
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "checklist")
                    .font(.appFont(28, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Finish setting up FrameTV")
                        .font(.appFont(22, weight: .bold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Add your movie database key to load posters and details, then connect your sources.")
                        .font(.appFont(16))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(Theme.Spacing.lg)
            .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .padding(.horizontal, Theme.Spacing.edge)
        }
        .frameRowStyle()
    }

    /// The Continue Watching shelf with resume badges and per-item Restart/Remove.
    private var continueWatchingRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Continue Watching")
                .font(Theme.Font.sectionTitle())
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal, Theme.Spacing.edge)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.lg) {
                    ForEach(library.continueWatching) { item in
                        ContinueWatchingCard(
                            item: item,
                            onPlay: { play(item) },
                            onRestart: { restart(item) },
                            onRemove: { withAnimation { library.clearProgress(for: item.id) } }
                        )
                    }
                }
                .padding(.horizontal, Theme.Spacing.edge)
            }
        }
    }
}

// MARK: - Discover tiles

/// A large painterly tile on the cinematic Home's Discover row.
struct DiscoverTile: Identifiable {
    enum Destination { case discover, library, settings }

    let id = UUID()
    let title: String
    let colors: [Color]
    let systemImage: String
    let destination: Destination

    /// The default set of Discover destinations, styled with distinct gradients.
    static let all: [DiscoverTile] = [
        DiscoverTile(title: "Watchlist",
                     colors: [Color(red: 0.55, green: 0.11, blue: 0.13),
                              Color(red: 0.30, green: 0.05, blue: 0.08)],
                     systemImage: "bookmark.fill",
                     destination: .discover),
        DiscoverTile(title: "Trending Movies",
                     colors: [Color(red: 0.10, green: 0.16, blue: 0.42),
                              Color(red: 0.04, green: 0.07, blue: 0.24)],
                     systemImage: "film.fill",
                     destination: .discover),
        DiscoverTile(title: "Trending Shows",
                     colors: [Color(red: 0.12, green: 0.34, blue: 0.30),
                              Color(red: 0.03, green: 0.16, blue: 0.15)],
                     systemImage: "tv.fill",
                     destination: .discover),
        DiscoverTile(title: "My Library",
                     colors: [Color(red: 0.34, green: 0.20, blue: 0.44),
                              Color(red: 0.15, green: 0.08, blue: 0.22)],
                     systemImage: "rectangle.stack.fill",
                     destination: .library)
    ]
}


// MARK: - Queue management

/// Reorder or remove queued titles. The queue is the "plan to watch" list, separate
/// from Favorites; it syncs across devices via iCloud KVS.
struct QueueManageView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if library.queuedItems.isEmpty {
                    Text("Your queue is empty. Add titles from any detail page.")
                        .font(.appFont(18))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(Theme.Spacing.lg)
                } else {
                    List {
                        ForEach(library.queuedItems) { item in
                            HStack(spacing: Theme.Spacing.md) {
                                PosterImage(url: item.posterURL,
                                            width: 44, height: 66)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.appFont(18, weight: .semibold))
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                        .lineLimit(1)
                                    if item.hasResumePoint {
                                        Text("In progress")
                                            .font(.appFont(14))
                                            .foregroundStyle(Theme.Colors.accent)
                                    }
                                }
                                Spacer()
                            }
                            .listRowBackground(Theme.Colors.card)
                        }
                        .onMove { library.moveInQueue(from: $0, to: $1) }
                        .onDelete { idx in
                            for i in idx { library.removeFromQueue(library.queuedItems[i]) }
                        }
                    }
                    #if os(iOS)
                    .scrollContentBackground(.hidden)
                    #endif
                }
            }
            .background(Theme.Colors.appBackground.ignoresSafeArea())
            .navigationTitle("Queue")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                #endif
            }
        }
    }
}
