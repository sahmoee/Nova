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
                                .fill(i == heroIndex ? Color.white : Color.white.opacity(0.35))
                                .frame(width: i == heroIndex ? 8 : 6,
                                       height: i == heroIndex ? 8 : 6)
                        }
                    }
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
        ZStack(alignment: .center) {
            // Painterly-style gradient background (an approximation of a textured
            // tile — not a copyrighted image).
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(
                    LinearGradient(colors: tile.colors,
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(
                            RadialGradient(colors: [.white.opacity(0.10), .clear],
                                           center: .topLeading, startRadius: 4, endRadius: 260)
                        )
                )
            Text(tile.title)
                .font(.appFont(28, weight: .heavy))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
                .padding(.horizontal, Theme.Spacing.md)
                .multilineTextAlignment(.center)
        }
        .frame(width: Theme.isCompact ? 300 : 360,
               height: Theme.isCompact ? 170 : 200)
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
        Text("FrameTV")
            .font(.appFont(28, weight: .heavy))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 6, y: 1)
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
    let destination: Destination

    /// The default set of Discover destinations, styled with distinct gradients.
    static let all: [DiscoverTile] = [
        DiscoverTile(title: "Watchlist",
                     colors: [Color(red: 0.55, green: 0.11, blue: 0.13),
                              Color(red: 0.30, green: 0.05, blue: 0.08)],
                     destination: .discover),
        DiscoverTile(title: "Trending Movies",
                     colors: [Color(red: 0.10, green: 0.16, blue: 0.42),
                              Color(red: 0.04, green: 0.07, blue: 0.24)],
                     destination: .discover),
        DiscoverTile(title: "Trending Shows",
                     colors: [Color(red: 0.12, green: 0.34, blue: 0.30),
                              Color(red: 0.03, green: 0.16, blue: 0.15)],
                     destination: .discover),
        DiscoverTile(title: "My Library",
                     colors: [Color(red: 0.34, green: 0.20, blue: 0.44),
                              Color(red: 0.15, green: 0.08, blue: 0.22)],
                     destination: .library)
    ]
}
