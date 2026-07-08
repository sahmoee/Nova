//
//  HomeView.swift
//  Astra
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
    @State private var detailTarget: CatalogItem?
    @State private var showCustomize = false
    @State private var heroIndex = 0
    @State private var showQueue = false
    @State private var searching = false
    @State private var shelfRefreshToken = UUID()
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var heroFocusNS

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.Colors.appBackground.ignoresSafeArea()

                if searching {
                    // Universal search takes over the screen while active: TMDB
                    // predictive suggestions, typo correction, and AI — the same
                    // experience as Discover. Tapping a result opens its detail.
                    ScrollView {
                        UniversalSearchView(prompt: "Search movies, shows, your library",
                                            recentsKey: "home.recentSearches")
                            .padding(Theme.Spacing.edge)
                            .frame(maxWidth: Theme.contentMaxWidth(1500), alignment: .leading)
                    }
                    .safeAreaInset(edge: .top) { searchDismissBar }
                } else if library.items.isEmpty && shelfStore.enabledShelves.isEmpty {
                    EmptyStateView(
                        systemImage: "play.tv",
                        title: "Welcome to Astra",
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
            .navigationDestination(item: $detailTarget) { catalog in
                ContentDetailView(item: catalog)
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
                homeSearchTrigger
                if !env.tmdb.hasKey {
                    setupBanner
                }
                if let hero = featuredItem {
                    FeaturedHero(item: hero) { play($0) }
                        .overlay(alignment: .topTrailing) { customizeButton }
                } else {
                    header
                }
                if !library.continueWatching.isEmpty {
                    continueWatchingRow
                }
                sharedRows
            }
            .padding(.bottom, Theme.Spacing.lg)
        }
        .refreshable { await refreshShelves() }
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
                homeSearchTrigger
                if !env.tmdb.hasKey {
                    setupBanner
                }

                heroCarousel

                if !library.continueWatching.isEmpty {
                    continueWatchingRow
                }

                sharedRows
            }
            .padding(.bottom, Theme.Spacing.lg)
        }
        .refreshable { await refreshShelves() }
        #if os(tvOS)
        .ignoresSafeArea(edges: .top)
        .focusScope(heroFocusNS)
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
                #if os(iOS)
                // Crossfade between heroes — auto-advance and manual swipes both fade
                // the artwork instead of sliding the page, like the tvOS top shelf.
                ZStack {
                    let safeIndex = min(heroIndex, items.count - 1)
                    let item = items[safeIndex]
                    FeaturedHero(item: item,
                                 height: heroCarouselHeight,
                                 badge: heroBadge(for: item),
                                 onMoreInfo: { openDetail($0) }) { play($0) }
                        .overlay(alignment: .topTrailing) { customizeButton }
                        .id(item.id)
                        .transition(.opacity)
                }
                .animation(.easeInOut(duration: 0.6), value: heroIndex)
                .frame(height: heroCarouselHeight)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 25)
                        .onEnded { value in
                            guard items.count > 1 else { return }
                            if value.translation.width < -40 {
                                heroIndex = (heroIndex + 1) % items.count
                            } else if value.translation.width > 40 {
                                heroIndex = (heroIndex - 1 + items.count) % items.count
                            }
                        }
                )
                #else
                TabView(selection: $heroIndex) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        FeaturedHero(item: item,
                                     height: heroCarouselHeight,
                                     badge: heroBadge(for: item),
                                     onMoreInfo: { openDetail($0) },
                                     playFocusNamespace: heroFocusNS) { play($0) }
                            .overlay(alignment: .topTrailing) { customizeButton }
                            .tag(idx)
                    }
                }
                .tabViewStyle(.automatic)
                .frame(height: heroCarouselHeight)
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
            // Gentle auto-advance so the hero rotates like a marquee; any manual
            // swipe just restarts the interval on the new index.
            .task(id: heroIndex) {
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled, items.count > 1 else { return }
                // Don't tick the marquee while backgrounded/inactive.
                guard scenePhase == .active else { return }
                withAnimation(.easeInOut(duration: 0.5)) {
                    heroIndex = (heroIndex + 1) % items.count
                }
            }
        }
    }

    /// The hero carousel height: tall and cinematic so the artwork fills the top of
    /// the screen rather than sitting as a short banner above blank space. The
    /// FeaturedHero inside is given the same height so image and frame always match.
    private var heroCarouselHeight: CGFloat {
        #if os(tvOS)
        return 620
        #else
        return Theme.isCompact ? 480 : 540
        #endif
    }

    /// The rows below the hero, shared verbatim by the classic and cinematic
    /// layouts so there is exactly one implementation of Queue, shelves, Recently
    /// Added, and Favorites.
    @ViewBuilder
    private var sharedRows: some View {
        if !library.queuedItems.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "Up Next in Queue") {
                    Button("Manage") { showQueue = true }
                        .font(.appFont(17, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                        .buttonStyle(AstraChipButtonStyle())
                }
                .padding(.horizontal, Theme.Spacing.edge)
                MediaRow(title: "",
                         items: Array(library.queuedItems.prefix(20))) { openDetail($0) }
            }
        }

        Group {
            ForEach(shelfStore.enabledShelves) { shelf in
                CatalogShelfRow(shelf: shelf)
            }
        }
        .id(shelfRefreshToken)

        if !library.recentlyAdded.isEmpty {
            MediaRow(title: "Recently Added",
                     items: library.recentlyAdded) { openDetail($0) }
        }
        if !library.favorites.isEmpty {
            MediaRow(title: "Favorites",
                     items: library.favorites) { openDetail($0) }
        }
    }

    /// Why-am-I-seeing-this chip for a hero item.
    private func heroBadge(for item: MediaItem) -> String? {
        if library.continueWatching.contains(where: { $0.id == item.id }) { return "Continue Watching" }
        if library.recentlyAdded.prefix(5).contains(where: { $0.id == item.id }) { return "Recently Added" }
        if item.isFavorite { return "Favorite" }
        return nil
    }

    /// Pull-to-refresh: drop the shelf cache and rebuild every shelf row.
    private func refreshShelves() async {
        await env.shelfLoader.clearCache()
        shelfRefreshToken = UUID()
    }

    /// Inline "Search" pill shown at the top of Home. Tapping it opens the universal
    /// search (TMDB predictive + AI) over the shelves. Placed inline (not in the nav
    /// bar) so it renders reliably on iPhone, iPad and tvOS.
    var homeSearchTrigger: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { searching = true }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.appFont(22))
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text("Search movies, shows, your library")
                    .font(.appFont(20))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(AstraListRowStyle())
        .padding(.horizontal, Theme.Spacing.edge)
    }

    /// A slim "Done" bar shown above the search results so the user can dismiss the
    /// search and return to their shelves.
    private var searchDismissBar: some View {
        HStack {
            Spacer()
            Button("Done") {
                withAnimation(.easeInOut(duration: 0.2)) { searching = false }
            }
            .font(.appFont(17, weight: .semibold))
            .foregroundStyle(Theme.Colors.accent)
            .padding(.horizontal, Theme.Spacing.edge)
            .padding(.vertical, Theme.Spacing.sm)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Featured hero selection

    /// The item to spotlight at the top: prefer the most recent Continue Watching,
    /// then the newest Recently Added, then the first favorite.
    private var featuredItem: MediaItem? {
        library.continueWatching.first
            ?? library.recentlyAdded.first
            ?? library.favorites.first
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
        .astraIconStyle()
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
                Text("Your personal media hub")
                    .font(Theme.Font.screenTitle())
                    .screenTitleStyle()
                    .foregroundStyle(Theme.Colors.textPrimary)
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
            .astraIconStyle()
        }
        .padding(.horizontal, Theme.Spacing.edge)
        .padding(.top, Theme.Spacing.lg)
    }

    // MARK: - Actions

    private func play(_ item: MediaItem) {
        Haptics.impact(.medium)
        selectedItem = item
    }

    /// Opens the full detail screen (stream picker flow) for a row item, matching the
    /// Discover tab. Used by Recently Added, Favorites, and Queue rows.
    private func openDetail(_ item: MediaItem) {
        detailTarget = item.asCatalogItem()
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
                    Text("Finish setting up Astra")
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
        .astraRowStyle()
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



