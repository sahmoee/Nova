//
//  HomeView.swift
//  Nova
//
//  Apple TV-style Watch Now experience shared by iPhone, iPad, and Apple TV.
//  The same information architecture is used everywhere while navigation, focus,
//  sheets, haptics, and device-only actions remain platform appropriate.
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
    @StateObject private var smbShares = SMBSharesModel()

    @State private var selectedItem: MediaItem?
    @State private var showCustomize = false
    @State private var showQueue = false
    @State private var showProfiles = false
    @State private var heroIndex = 0
    @State private var shelfRefreshToken = UUID()
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var heroFocusNS

    enum HomeRoute: Hashable {
        case liveTV
        case sources
        case collections
        case history
        case smartCollections
        case watchStats
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.Colors.appBackground.ignoresSafeArea()

                if library.items.isEmpty && shelfStore.enabledShelves.isEmpty {
                    welcomeState
                } else {
                    watchNowContent
                }
            }
            .fullScreenCover(item: $selectedItem) { item in
                // Present the player as a full-screen cover so no tab bar, sidebar,
                // or mini-bar remains visible during playback on any platform.
                NavigationStack { PlayerView(item: item) }
            }
            .navigationDestination(for: CatalogItem.self) { item in
                ContentDetailView(item: item)
            }
            .navigationDestination(for: HomeRoute.self) { route in
                destination(for: route)
            }
            .sheet(isPresented: $showCustomize) {
                HomeCustomizeView()
            }
            .sheet(isPresented: $showQueue) {
                QueueManageView()
            }
            .sheet(isPresented: $showProfiles) {
                ViewingProfileSwitcherView(store: profiles)
            }
        }
    }

    // MARK: - Watch Now

    private var watchNowContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.rowGap) {
                topBar

                if !env.tmdb.hasKey {
                    setupBanner
                }

                heroCarousel

                AppleTVUpNextRail(
                    items: PersonalizedHomeEngine.upNext(library: library),
                    onPlay: play,
                    onRestart: restart,
                    onRemove: removeFromUpNext,
                    onManage: { showQueue = true }
                )

                if profiles.preferences.showQuickAccess {
                    AppleTVQuickAccessRow(items: quickAccessItems)
                }

                if profiles.preferences.showBecauseYouWatched,
                   let anchor = library.recentlyWatched.first {
                    BecauseYouWatchedCatalogRail(anchor: anchor) { catalog in
                        path.append(catalog)
                    }
                }

                ForEach(primarySmartRails) { rail in
                    AppleTVSmartRailView(rail: rail, onSelect: openDetail)
                }

                // Editorial catalog rows remain network-backed and user-customizable,
                // but now sit inside the same Watch Now feed as personal rails.
                Group {
                    ForEach(shelfStore.enabledShelves) { shelf in
                        CatalogShelfRow(shelf: shelf, showSourceLabel: false)
                    }
                }
                .id(shelfRefreshToken)

                if profiles.preferences.showSourceHub {
                    AppleTVSourceHub(items: sourceHealthItems) {
                        path.append(HomeRoute.sources)
                    }
                }

                if profiles.preferences.showSmartCollections {
                    smartCollectionsFooter
                }
            }
            .padding(.bottom, Theme.Spacing.xl)
        }
        #if os(iOS)
        .refreshable { await refreshShelves() }
        #endif
        #if os(tvOS)
        .ignoresSafeArea(edges: .top)
        .focusScope(heroFocusNS)
        #endif
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.sm) {
            Text("NOVA")
                .font(.appFont(PlatformCapabilities.platform == .appleTV ? 38 : 30, weight: .black))
                .tracking(2.5)
                .foregroundStyle(Theme.Colors.accent)
                .accessibilityLabel("Nova Home")
            if !Theme.isCompact {
                Text("WATCH NOW")
                    .font(.appFont(13, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            Button {
                nav.selection = .discover
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.appFont(20, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(width: 42, height: 42)
                    .background(.thinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(NovaListRowStyle())
            .accessibilityLabel("Search")

            AppleTVProfileButton(store: profiles) {
                showProfiles = true
            }
        }
        .padding(.horizontal, Theme.Spacing.edge)
        .padding(.top, PlatformCapabilities.platform == .appleTV ? Theme.Spacing.xl : Theme.Spacing.md)
    }

    // MARK: - Hero

    private var heroItems: [MediaItem] {
        let topPicks = PersonalizedHomeEngine.rails(library: library, profile: profiles.activeProfile)
            .first(where: { $0.kind == .topPicks })?.items ?? []
        var seen = Set<String>()
        return (library.continueWatching + topPicks + library.recentlyAdded + library.favorites)
            .filter { seen.insert($0.contentKey).inserted }
            .prefix(10)
            .map { $0 }
    }

    @ViewBuilder
    private var heroCarousel: some View {
        let items = heroItems
        if items.isEmpty {
            fallbackHeader
        } else {
            VStack(spacing: Theme.Spacing.sm) {
                #if os(iOS)
                ZStack {
                    let safeIndex = min(heroIndex, items.count - 1)
                    let item = items[safeIndex]
                    FeaturedHero(item: item,
                                 height: PlatformCapabilities.homeHeroHeight,
                                 badge: heroBadge(for: item),
                                 onMoreInfo: openDetail) { play($0) }
                        .overlay(alignment: .topTrailing) { customizeButton }
                        .id(item.id)
                        .transition(.opacity)
                }
                .animation(profiles.preferences.reduceArtworkMotion ? nil : .easeInOut(duration: 0.55),
                           value: heroIndex)
                .frame(height: PlatformCapabilities.homeHeroHeight)
                .contentShape(Rectangle())
                .simultaneousGesture(
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
                ZStack {
                    let safeIndex = min(heroIndex, items.count - 1)
                    let item = items[safeIndex]
                    FeaturedHero(item: item,
                                 height: PlatformCapabilities.homeHeroHeight,
                                 badge: heroBadge(for: item),
                                 onMoreInfo: openDetail,
                                 playFocusNamespace: heroFocusNS) { play($0) }
                        .overlay(alignment: .topTrailing) { customizeButton }
                        .id(item.id)
                        .transition(.opacity)
                }
                .animation(profiles.preferences.reduceArtworkMotion ? nil : .easeInOut(duration: 0.55),
                           value: heroIndex)
                .frame(height: PlatformCapabilities.homeHeroHeight)
                #endif

                if items.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(items.indices, id: \.self) { index in
                            Capsule()
                                .fill(index == heroIndex ? Color.white : Color.white.opacity(0.32))
                                .frame(width: index == heroIndex ? 18 : 6, height: 6)
                        }
                    }
                    .animation(.easeOut(duration: 0.18), value: heroIndex)
                    // Accessibility: the dots are decorative; VoiceOver reads the hero itself.
                    .accessibilityHidden(true)
                }
            }
            .task(id: heroIndex) {
                guard profiles.preferences.autoAdvanceHero,
                      !profiles.preferences.reduceArtworkMotion,
                      items.count > 1 else { return }
                try? await Task.sleep(for: .seconds(9))
                guard !Task.isCancelled, scenePhase == .active else { return }
                withAnimation(.easeInOut(duration: 0.5)) {
                    heroIndex = (heroIndex + 1) % items.count
                }
            }
        }
    }

    private func heroBadge(for item: MediaItem) -> String? {
        if item.hasResumePoint { return "Up Next" }
        if library.queueIDs.contains(item.id) { return "In Your Queue" }
        if item.isFavorite { return "Favorite" }
        if item.addedDate > Date().addingTimeInterval(-60 * 60 * 24 * 14) { return "Recently Added" }
        return "Top Pick"
    }

    private var customizeButton: some View {
        Button { showCustomize = true } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.appFont(20, weight: .semibold))
                .foregroundStyle(.white)
                .padding(Theme.Spacing.sm)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(NovaListRowStyle())
        // Accessibility: icon-only button needs a spoken name and purpose.
        .accessibilityLabel("Customize Home")
        .accessibilityHint("Choose which shelves appear on Home")
        .padding(.horizontal, Theme.Spacing.edge)
        .padding(.top, Theme.Spacing.sm)
        #if os(tvOS)
        .safeAreaPadding(.top)
        .safeAreaPadding(.trailing)
        #endif
    }

    // MARK: - Personal rails

    private var primarySmartRails: [SmartHomeRail] {
        let excluded: Set<SmartHomeRailKind> = [.becauseYouWatched, .recentlyAdded]
        return PersonalizedHomeEngine.distinctRails(
            library: library,
            profile: profiles.activeProfile,
            excluding: PersonalizedHomeEngine.upNext(library: library)
        )
            .filter { !excluded.contains($0.kind) }
            .filter { rail in
                if rail.kind == .recentlyWatched { return profiles.preferences.showWatchHistory }
                return true
            }
            .prefix(7)
            .map { $0 }
    }

    private var smartCollectionsFooter: some View {
        Button { path.append(HomeRoute.smartCollections) } label: {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "rectangle.3.group.fill")
                    .font(.appFont(34, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Browse All Smart Collections")
                        .font(.appFont(21, weight: .bold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Finish Tonight, 4K, Binge Next, personal media, history, and more")
                        .font(.appFont(15))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding(Theme.Spacing.lg)
            .background(.thinMaterial,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.largeCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.largeCard, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, Theme.Spacing.edge)
        }
        .buttonStyle(NovaListRowStyle())
    }

    // MARK: - Quick access / source hub

    private var quickAccessItems: [AppleTVQuickAccessItem] {
        [
            AppleTVQuickAccessItem(id: "library", title: "Library", subtitle: "Everything you saved", systemImage: "rectangle.stack.fill") {
                nav.selection = .library
            },
            AppleTVQuickAccessItem(id: "live", title: "Live TV", subtitle: "Channels and guide", systemImage: "dot.radiowaves.left.and.right") {
                path.append(HomeRoute.liveTV)
            },
            AppleTVQuickAccessItem(id: "collections", title: "Collections", subtitle: "Your custom lists", systemImage: "rectangle.stack.badge.plus") {
                path.append(HomeRoute.collections)
            },
            AppleTVQuickAccessItem(id: "history", title: "Watch History", subtitle: "Recently played titles", systemImage: "clock.arrow.circlepath") {
                path.append(HomeRoute.history)
            },
            AppleTVQuickAccessItem(id: "smart", title: "Smart Collections", subtitle: "Automatic viewing lanes", systemImage: "sparkles.rectangle.stack") {
                path.append(HomeRoute.smartCollections)
            },
            AppleTVQuickAccessItem(id: "sources", title: "Sources", subtitle: "Accounts, addons, and shares", systemImage: "point.3.connected.trianglepath.dotted") {
                path.append(HomeRoute.sources)
            }
        ]
    }

    private var sourceHealthItems: [SourceHealthItem] {
        SourceHealth.all(addonStore: env.addonStore, smbShareCount: smbShares.shares.count)
    }

    // MARK: - Destinations

    @ViewBuilder
    private func destination(for route: HomeRoute) -> some View {
        switch route {
        case .liveTV:
            LiveTVView()
        case .sources:
            SourcesView(path: $path)
        case .collections:
            CollectionsView()
        case .history:
            WatchHistoryTimelineView()
        case .smartCollections:
            SmartCollectionsView()
        case .watchStats:
            WatchStatsView()
        }
    }

    // MARK: - Actions

    private func play(_ item: MediaItem) {
        Haptics.impact(.medium)
        selectedItem = item
    }

    private func openDetail(_ item: MediaItem) {
        path.append(item.asCatalogItem())
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
        VStack(spacing: Theme.Spacing.lg) {
            EmptyStateView(
                systemImage: "play.tv.fill",
                title: "Welcome to Nova",
                message: "Connect your sources and Nova will build a personalized Watch Now experience across iPhone, iPad, and Apple TV.",
                actionTitle: "Set Up Sources",
                action: { nav.selection = .settings }
            )
            AppleTVProfileButton(store: profiles) { showProfiles = true }
        }
    }

    private var setupBanner: some View {
        Button { nav.selection = .settings } label: {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "checklist")
                    .font(.appFont(28, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Finish setting up Nova")
                        .font(.appFont(20, weight: .bold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Add your TMDB key for artwork, details, editorial shelves, and recommendations.")
                        .font(.appFont(15))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(Theme.Spacing.lg)
            .background(.thinMaterial,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.largeCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.largeCard, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, Theme.Spacing.edge)
        }
        .buttonStyle(NovaListRowStyle())
    }

    private var fallbackHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Your personal media hub")
                    .font(Theme.Font.screenTitle())
                    .screenTitleStyle()
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Add something to your queue or library to build Watch Now.")
                    .font(.appFont(17))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            customizeButton
        }
        .padding(.horizontal, Theme.Spacing.edge)
        .padding(.vertical, Theme.Spacing.lg)
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
