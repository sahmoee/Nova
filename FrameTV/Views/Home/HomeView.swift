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
    @StateObject private var shelfStore = HomeShelfStore.shared
    @State private var selectedItem: MediaItem?
    @State private var showCustomize = false

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()

                if library.items.isEmpty && shelfStore.enabledShelves.isEmpty {
                    EmptyStateView(
                        systemImage: "play.tv",
                        title: "Welcome to FrameTV",
                        message: "Add a source or a direct link in Settings to start building your library.",
                        actionTitle: "Set Up Sources",
                        action: { nav.selection = .settings }
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Spacing.rowGap) {
                            // Cinematic featured hero spotlighting one item, with a
                            // compact title bar overlaid for branding + customize.
                            if let hero = featuredItem {
                                FeaturedHero(item: hero) { play($0) }
                                    .overlay(alignment: .topTrailing) { customizeButton }
                                    .overlay(alignment: .topLeading) { brandMark }
                            } else {
                                header
                            }

                            if !library.continueWatching.isEmpty {
                                MediaRow(title: "Continue Watching",
                                         items: library.continueWatching,
                                         wide: true) { play($0) }
                            }

                            // User-configured catalog shelves (Trakt, TMDB, addons).
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
                    // On tvOS the hero image bleeds to the top edge for a cinematic
                    // look (no status bar there). On iPhone/iPad we keep the normal
                    // safe area so the brand header and all content stay below the
                    // status bar and scroll beneath it.
                    #if os(tvOS)
                    .ignoresSafeArea(edges: featuredItem != nil ? .top : [])
                    #endif
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
}
