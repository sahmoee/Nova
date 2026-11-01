//
//  HomeView.swift
//  Nova
//
//  Omni-style Home shared by Apple TV, iPad, Mac and iPhone: a logo-first featured
//  hero fed by the Top Row catalogs, Continue Watching, the Top Row itself, then the
//  remaining catalog rows in the user's order. On tvOS the hero collapses when focus
//  moves into the rows and previews the focused title. See OMNI_STYLE_REDESIGN.md.
//

import SwiftUI

struct HomeView: View {
    @Binding var path: NavigationPath
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var nav: NavigationCoordinator
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var settings: SettingsStore

    @StateObject private var shelfStore = HomeShelfStore.shared
    @StateObject private var profiles = ViewingProfileStore.shared

    @State private var selectedItem: MediaItem?
    @State private var showProfiles = false
    @State private var heroItems: [CatalogItem] = []
    @State private var previewItem: CatalogItem?
    @State private var heroCollapsed = false
    @State private var shelfRefreshToken = UUID()
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var homeScope

    enum HomeRoute: Hashable {
        case liveTV
        case sources
        case collections
        case history
        case smartCollections
        case watchStats
        case streams(CatalogItem)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()
                if library.items.isEmpty && shelfStore.enabledShelves.isEmpty {
                    welcomeState
                } else {
                    homeContent
                }
            }
            #if os(tvOS)
            .tvRootMenu()
            #else
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .fullScreenCover(item: $selectedItem) { item in
                NavigationStack { PlayerView(item: item) }
            }
            .navigationDestination(for: CatalogItem.self) { item in
                ContentDetailView(item: item)
            }
            .navigationDestination(for: HomeRoute.self) { route in
                destination(for: route)
            }
            #if os(iOS)
            .sheet(isPresented: $showProfiles) {
                ViewingProfileSwitcherView(store: profiles)
            }
            #endif
        }
    }

    // MARK: - Content

    private var homeContent: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: OmniStyle.rowSpacing) {
                        OmniHeroView(
                            items: heroItems,
                            previewItem: previewItem,
                            collapsed: heroCollapsed,
                            height: heroHeight(in: geometry.size.height),
                            isActive: nav.selection == .home && path.isEmpty && selectedItem == nil
                                && scenePhase == .active,
                            onPlay: playFeatured,
                            onOpen: { path.append($0) },
                            onFocusChange: { focused in
                                if focused { setCollapsed(false, proxy: proxy) }
                            }
                        )
                        .id("hero")
                        .overlay(alignment: .top) { topBar }

                        #if os(iOS)
                        if !env.tmdb.hasKey { setupBanner }
                        if Theme.isCompact { browseChips }
                        #endif

                        OmniContinueWatchingRow(
                            items: PersonalizedHomeEngine.upNext(library: library),
                            onPlay: play,
                            onRestart: restart,
                            onRemove: removeFromUpNext,
                            onFocusCard: { previewItem = nil; setCollapsed(true, proxy: proxy) }
                        )

                        Group {
                            ForEach(Array(shelfStore.topRowShelves.enumerated()), id: \.element.id) { offset, shelf in
                                OmniShelfRow(shelf: shelf,
                                             onFocusItem: { focusRow($0, proxy: proxy) },
                                             onLoaded: { items in
                                                 if offset == 0 { feedHero(items) }
                                             })
                            }
                            ForEach(shelfStore.remainingShelves) { shelf in
                                OmniShelfRow(shelf: shelf, onFocusItem: { focusRow($0, proxy: proxy) })
                            }
                        }
                        .id(shelfRefreshToken)
                    }
                    .padding(.bottom, 80)
                }
                .scrollClipDisabled()
                #if os(iOS)
                .refreshable { await refreshShelves() }
                #endif
            }
        }
        .ignoresSafeArea(edges: .top)
        .onAppear {
            if heroItems.isEmpty { heroItems = historyHeroFallback }
        }
    }

    private func heroHeight(in pageHeight: CGFloat) -> CGFloat {
        #if os(tvOS)
        pageHeight * (heroCollapsed ? OmniStyle.heroCollapsedFraction : OmniStyle.heroHeightFraction)
        #else
        Theme.isPad ? max(460, pageHeight * 0.62) : max(420, pageHeight * 0.6)
        #endif
    }

    /// The Top Row feeds the hero; history covers installs with no catalogs yet.
    private func feedHero(_ items: [CatalogItem]) {
        let featured = items.filter { $0.backdropURL != nil }.prefix(8)
        heroItems = featured.isEmpty ? historyHeroFallback : Array(featured)
    }

    private var historyHeroFallback: [CatalogItem] {
        Array(library.viewingHistoryHeroItems.prefix(8)).map { $0.asCatalogItem() }
    }

    private func focusRow(_ item: CatalogItem, proxy: ScrollViewProxy) {
        previewItem = item
        setCollapsed(true, proxy: proxy)
    }

    private func setCollapsed(_ collapsed: Bool, proxy: ScrollViewProxy) {
        #if os(tvOS)
        guard heroCollapsed != collapsed else { return }
        withAnimation(Theme.isReduceMotion ? nil : .easeInOut(duration: 0.3)) {
            heroCollapsed = collapsed
            if !collapsed { proxy.scrollTo("hero", anchor: .top) }
        }
        #endif
    }

    // MARK: - Chrome

    @ViewBuilder
    private var topBar: some View {
        #if os(iOS)
        HStack {
            Text("Nova")
                .font(.appFont(Theme.isPad ? 30 : 26, weight: .semibold, design: .serif))
                .foregroundStyle(.white)
                .accessibilityLabel("Nova Home")
            Spacer()
            Button { showProfiles = true } label: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Switch Profile")
        }
        .padding(.horizontal, OmniStyle.edge)
        .padding(.top, 54)
        #else
        EmptyView()
        #endif
    }

    #if os(iOS)
    /// iPhone has no sidebar, so the catalog groups sit under the hero as chips.
    private var browseChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                chip("Movies", systemImage: "film") { nav.selection = .movies }
                chip("Series", systemImage: "tv") { nav.selection = .series }
                if !env.liveTVSources.allChannels.isEmpty {
                    chip("Live TV", systemImage: "dot.radiowaves.left.and.right") { path.append(HomeRoute.liveTV) }
                }
                chip("Collections", systemImage: "rectangle.stack") { path.append(HomeRoute.collections) }
            }
            .padding(.horizontal, OmniStyle.edge)
        }
    }

    private func chip(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.appFont(15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(Capsule().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
    #endif

    // MARK: - Destinations

    @ViewBuilder
    private func destination(for route: HomeRoute) -> some View {
        switch route {
        case .liveTV:
            LiveTVView()
        case .sources:
            SourcesView()
        case .collections:
            CollectionsView()
        case .history:
            WatchHistoryTimelineView()
        case .smartCollections:
            SmartCollectionsView()
        case .watchStats:
            WatchStatsView()
        case .streams(let item):
            StreamPickerView(catalog: item, episode: nil)
        }
    }

    // MARK: - Actions

    /// Movies go straight to streams like Omni's hero; series open their page so
    /// the viewer can pick an episode.
    private func playFeatured(_ item: CatalogItem) {
        if item.isSeries { path.append(item) } else { path.append(HomeRoute.streams(item)) }
    }

    private func play(_ item: MediaItem) {
        Haptics.impact(.medium)
        selectedItem = item
    }

    private func restart(_ item: MediaItem) {
        library.clearProgress(for: item.id)
        var fresh = item
        fresh.lastPlayedPosition = 0
        selectedItem = fresh
    }

    private func removeFromUpNext(_ item: MediaItem) {
        withAnimation {
            library.clearProgress(for: item.id)
            library.removeFromQueue(item)
        }
    }

    private func refreshShelves() async {
        await env.shelfLoader.clearCache()
        shelfRefreshToken = UUID()
    }

    // MARK: - Setup / empty states

    private var welcomeState: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Nova")
                .font(.appFont(welcomeTitle * 0.55, weight: .semibold, design: .serif))
                .foregroundStyle(.white.opacity(0.7))
            Text("All your entertainment.\nOne place.")
                .font(.appFont(welcomeTitle, weight: .bold))
                .foregroundStyle(.white)
            Text("Connect a media source or install an addon, and Nova will build your Home from its catalogs.")
                .font(.appFont(welcomeTitle * 0.38))
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: 760, alignment: .leading)
            Button { nav.selection = .settings } label: {
                Label("Set Up Sources", systemImage: "gearshape")
                    .font(.appFont(welcomeTitle * 0.36, weight: .semibold))
            }
            .buttonStyle(OmniHeroButtonStyle(prominent: true))
            .padding(.top, 10)
        }
        .padding(OmniStyle.edge)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(.bottom, 60)
    }

    private var welcomeTitle: CGFloat {
        #if os(tvOS)
        64
        #else
        Theme.isPad ? 46 : 34
        #endif
    }

    private var setupBanner: some View {
        Button { nav.selection = .settings } label: {
            HStack(spacing: 14) {
                Image(systemName: "checklist")
                    .font(.system(size: 22, weight: .semibold))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Finish setting up Nova").font(.appFont(16, weight: .bold))
                    Text("Add a TMDB key for artwork, logos and catalog rows.")
                        .font(.appFont(13))
                        .foregroundStyle(.white.opacity(0.65))
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.5))
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: OmniStyle.cardRadius, style: .continuous))
            .padding(.horizontal, OmniStyle.edge)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Queue management

struct QueueManageView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if library.queuedItems.isEmpty {
                    EmptyStateView(systemImage: "text.badge.plus",
                                   title: "Your queue is empty",
                                   message: "Add titles from any detail page or poster menu.")
                } else {
                    List {
                        ForEach(library.queuedItems) { item in
                            HStack(spacing: Theme.Spacing.md) {
                                PosterImage(url: item.posterURL, width: 44, height: 66)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.displayTitle)
                                        .font(.appFont(18, weight: .semibold))
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                        .lineLimit(1)
                                    Text(item.hasResumePoint ? "In progress" : "Ready to watch")
                                        .font(.appFont(14))
                                        .foregroundStyle(item.hasResumePoint ? Theme.Colors.accent : Theme.Colors.textSecondary)
                                }
                                Spacer()
                            }
                            // Accessibility: read poster, title, and status as one element.
                            .accessibilityElement(children: .combine)
                            .listRowBackground(Theme.Colors.card)
                        }
                        .onMove { library.moveInQueue(from: $0, to: $1) }
                        .onDelete { indexes in
                            for index in indexes { library.removeFromQueue(library.queuedItems[index]) }
                        }
                    }
                    #if os(iOS)
                    .scrollContentBackground(.hidden)
                    #endif
                }
            }
            .background(Theme.Colors.appBackground.ignoresSafeArea())
            .navigationTitle("Up Next")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
                #endif
            }
        }
    }
}
