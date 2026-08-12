//
//  RootView.swift
//  Nova
//
//  Adaptive Apple TV-style shell. iPhone uses a native bottom tab bar, iPad keeps a
//  persistent sidebar, and tvOS uses the platform's focus-driven tab navigation.
//  Every tab owns an independent NavigationStack through NavigationCoordinator.
//

import SwiftUI

struct RootView: View {
    @StateObject private var nav = NavigationCoordinator()
    @StateObject private var nowPlaying = NowPlayingStore.shared
    @StateObject private var accentManager = AccentManager.shared
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var settings: SettingsStore

    @State private var offerRestore = false
    @State private var showWhatsNew = false
    @AppStorage("hasSeenPersonalMediaDisclosure") private var hasSeenDisclosure = false
    @State private var reopenItem: MediaItem?
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        rootContent
            .environmentObject(nav)
            .environment(\.dynamicAccent, accentManager.accent)
            .tint(accentManager.accent)
            .onOpenURL { nav.handle(url: $0) }
            .fullScreenCover(item: $reopenItem) { item in
                // NavigationStack so the player's internal next-episode navigation
                // works, and the cover guarantees nothing else is visible behind it.
                NavigationStack {
                    PlayerView(item: item, autoResume: true)
                }
                .environmentObject(env)
                .environmentObject(nav)
            }
            .toastHost()
            .fullScreenCover(isPresented: Binding(
                get: { !hasSeenDisclosure },
                set: { newValue in if !newValue { hasSeenDisclosure = true } }
            )) {
                PersonalMediaDisclosureView { hasSeenDisclosure = true }
            }
            .onAppear(perform: maybeOfferRestore)
            .onAppear(perform: autoSyncFromCloud)
            .onAppear(perform: maybeShowWhatsNew)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    autoSyncFromCloud()
                } else if phase == .background {
                    BackupManager.shared.createBackup()
                }
            }
            .sheet(isPresented: $showWhatsNew) {
                WhatsNewView(note: WhatsNewTracker.shared.currentNote) {
                    WhatsNewTracker.shared.markSeen()
                    showWhatsNew = false
                }
                #if os(iOS)
                .presentationDragIndicator(.visible)
                #endif
            }
            .alert("Restore your setup?", isPresented: $offerRestore) {
                Button("Restore from iCloud") {
                    if BackupManager.shared.restoreFromCloud() {
                        ToastCenter.shared.show("Restored from iCloud", systemImage: "checkmark.icloud.fill")
                    }
                }
                Button("Not Now", role: .cancel) {}
            } message: {
                if let info = BackupManager.shared.availableSnapshotInfo() {
                    Text("Found a backup from \(info.device). Restore your preferences, sources, addons, and logins onto this device?")
                } else {
                    Text("Found a backup in iCloud. Restore it onto this device?")
                }
            }
    }

    // MARK: - Adaptive shell

    @ViewBuilder
    private var rootContent: some View {
        #if os(tvOS)
        televisionTabRoot
        #else
        if horizontalSizeClass == .regular {
            iPadSidebarRoot
        } else {
            iPhoneTabRoot
        }
        #endif
    }

    #if os(iOS)
    /// iPhone mirrors the Apple TV app's familiar bottom navigation and leaves each
    /// section mounted, preserving scroll position and navigation history.
    private var iPhoneTabRoot: some View {
        tabView
            .safeAreaInset(edge: .bottom, spacing: 0) { nowPlayingBar }
            .toolbarBackground(.ultraThinMaterial, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
    }
    #endif

    #if os(tvOS)
    /// tvOS lets SwiftUI render the native focusable television tab strip. This is
    /// more predictable than intercepting the remote Menu button with a custom panel.
    private var televisionTabRoot: some View {
        ZStack(alignment: .bottom) {
            Theme.Colors.appBackground.ignoresSafeArea()
            tabView
            nowPlayingBar
                .padding(.horizontal, Theme.Spacing.edge)
                .padding(.bottom, Theme.Spacing.sm)
        }
    }
    #endif

    private var tabView: some View {
        TabView(selection: nav.selectionBinding) {
            HomeView(path: $nav.homePath)
                .tabItem { Label(AppTab.home.title, systemImage: AppTab.home.systemImage) }
                .tag(AppTab.home)

            DiscoverView(path: $nav.discoverPath)
                .tabItem { Label(AppTab.discover.title, systemImage: AppTab.discover.systemImage) }
                .tag(AppTab.discover)

            LibraryView(path: $nav.libraryPath)
                .tabItem { Label(AppTab.library.title, systemImage: AppTab.library.systemImage) }
                .tag(AppTab.library)

            AIView(path: $nav.aiPath)
                .tabItem { Label(AppTab.ai.title, systemImage: AppTab.ai.systemImage) }
                .tag(AppTab.ai)

            SettingsView(path: $nav.settingsPath)
                .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage) }
                .tag(AppTab.settings)
        }
        .environmentObject(env)
        .environmentObject(env.library)
        .environmentObject(env.progress)
        .environmentObject(settings)
    }

    #if os(iOS)
    /// iPad uses the Apple TV / Music-style persistent sidebar with the active
    /// section filling the detail column. The mini-player remains pinned above the
    /// bottom safe area and never replaces the sidebar.
    private var iPadSidebarRoot: some View {
        NavigationSplitView {
            List(AppTab.allCases, id: \.self, selection: sidebarSelection) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .font(.appFont(18, weight: .medium))
                    .tag(tab)
                    .padding(.vertical, 4)
            }
            .navigationTitle("Nova")
            .listStyle(.sidebar)
        } detail: {
            ZStack(alignment: .bottom) {
                Theme.Colors.appBackground.ignoresSafeArea()
                activeScreen
                    .safeAreaInset(edge: .bottom, spacing: 0) { nowPlayingBar }
            }
        }
        .tint(accentManager.accent)
    }

    private var sidebarSelection: Binding<AppTab?> {
        Binding(
            get: { nav.selection },
            set: { newValue in
                guard let tab = newValue else { return }
                if tab == nav.selection { nav.popToRoot(tab) }
                nav.selection = tab
            }
        )
    }
    #endif

    @ViewBuilder
    private var activeScreen: some View {
        Group {
            switch nav.selection {
            case .home:     HomeView(path: $nav.homePath)
            case .discover: DiscoverView(path: $nav.discoverPath)
            case .library:  LibraryView(path: $nav.libraryPath)
            case .ai:       AIView(path: $nav.aiPath)
            case .settings: SettingsView(path: $nav.settingsPath)
            }
        }
        .environmentObject(env)
        .environmentObject(env.library)
        .environmentObject(env.progress)
        .environmentObject(settings)
    }

    // MARK: - Now Playing mini-player

    /// Whether the mini bar is currently on screen, driving its show/hide animation.
    private var miniBarVisible: Bool {
        nowPlaying.current != nil && reopenItem == nil && !nowPlaying.playerPresented
    }

    private var nowPlayingBar: some View {
        // ZStack container so the bar's insertion/removal transition is animated
        // (springs in/out) instead of snapping when playback state flips.
        ZStack {
            nowPlayingBarContent
        }
        .animation(Theme.Motion.spring, value: miniBarVisible)
    }

    @ViewBuilder
    private var nowPlayingBarContent: some View {
        if let item = nowPlaying.current, reopenItem == nil, !nowPlaying.playerPresented {
            let isTV = PlatformCapabilities.platform == .appleTV
            VStack(spacing: 0) {
                HStack(spacing: isTV ? Theme.Spacing.md : Theme.Spacing.sm) {
                    Button { reopenItem = item } label: {
                        HStack(spacing: isTV ? Theme.Spacing.md : Theme.Spacing.sm) {
                            PosterImage(url: item.posterURL,
                                        width: isTV ? 78 : 50,
                                        height: isTV ? 78 : 50)
                                .clipShape(RoundedRectangle(cornerRadius: isTV ? 10 : 7,
                                                            style: .continuous))

                            VStack(alignment: .leading, spacing: isTV ? 5 : 2) {
                                Text(item.displayTitle)
                                    .font(.appFont(isTV ? 20 : 16, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(nowPlayingSubtitle(item))
                                    .font(.appFont(isTV ? 16 : 13))
                                    .foregroundStyle(.white.opacity(0.68))
                                    .lineLimit(1)
                                    // Roll the percent digits instead of hard-swapping.
                                    .contentTransition(.numericText())
                                    .animation(.easeInOut(duration: 0.3), value: nowPlaying.progress)
                            }
                            Spacer(minLength: Theme.Spacing.sm)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Now Playing, \(item.displayTitle)")
                    .accessibilityValue(nowPlayingSubtitle(item))
                    .accessibilityHint("Open the player")

                    Button {
                        // Light tap confirms resuming playback (no-op on tvOS).
                        Haptics.impact(.light)
                        reopenItem = item
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.appFont(isTV ? 24 : 18, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(width: isTV ? 58 : 42, height: isTV ? 58 : 42)
                            .background(.white, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Resume playback")
                    .accessibilityHint("Open the player and continue \(item.displayTitle)")

                    Button { withAnimation { nowPlaying.clear() } } label: {
                        Image(systemName: "xmark")
                            .font(.appFont(isTV ? 21 : 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.76))
                            .frame(width: isTV ? 50 : 38, height: isTV ? 50 : 38)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close Now Playing")
                    .accessibilityHint("Hide the mini player")
                }
                .padding(.horizontal, isTV ? Theme.Spacing.md : 12)
                .padding(.vertical, isTV ? Theme.Spacing.sm : 8)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.14))
                        Capsule().fill(Theme.Colors.accent)
                            .frame(width: geo.size.width * nowPlaying.progress)
                    }
                }
                // Glide the progress capsule to new widths instead of jumping.
                .animation(.linear(duration: 0.3), value: nowPlaying.progress)
                .frame(height: isTV ? 5 : 3)
                .padding(.horizontal, isTV ? Theme.Spacing.md : 12)
                .padding(.bottom, isTV ? 12 : 8)
                .accessibilityHidden(true)
            }
            .background(.regularMaterial,
                        in: RoundedRectangle(cornerRadius: isTV ? 20 : 16,
                                             style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: isTV ? 20 : 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.36), radius: 22, y: 10)
            .padding(.horizontal, isTV ? 0 : 10)
            .padding(.bottom, isTV ? 0 : 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func nowPlayingSubtitle(_ item: MediaItem) -> String {
        let percent = Int(nowPlaying.progress * 100)
        let episode = item.subtitleLine.isEmpty ? nil : item.subtitleLine
        if let episode {
            return "\(episode) · \(percent)% complete"
        }
        return percent > 0 ? "Paused · \(percent)% complete" : "Paused · Resume"
    }

    // MARK: - Lifecycle

    private func maybeShowWhatsNew() {
        guard !offerRestore else { return }
        if WhatsNewTracker.shared.shouldShow() { showWhatsNew = true }
    }

    private func autoSyncFromCloud() {
        if BackupManager.shared.autoSyncOnLaunch() {
            ToastCenter.shared.show("Synced from iCloud", systemImage: "checkmark.icloud.fill")
        }
    }

    private func maybeOfferRestore() {
        let defaults = UserDefaults.standard
        let launchedKey = "app.hasLaunchedBefore"
        guard !defaults.bool(forKey: launchedKey) else { return }
        defaults.set(true, forKey: launchedKey)
        WhatsNewTracker.shared.markSeen()
        if env.library.items.isEmpty, BackupManager.shared.hasCloudSnapshot() {
            offerRestore = true
        }
    }
}


// MARK: - Anime tab (boxd feature #3)
// A dedicated anime catalog: Japanese-origin Animation titles across several shelves,
// each poster routing into the shared ContentDetailView. Uses the app's boxd-themed
// tokens so it matches the rest of Nova.
struct AnimeView: View {
    @EnvironmentObject private var env: AppEnvironment

    private struct AnimeShelf: Identifiable {
        let id = UUID(); let title: String; let items: [CatalogItem]
    }
    @State private var shelves: [AnimeShelf] = []
    @State private var loaded = false

    var body: some View {
        ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.rowGap) {
                    if !loaded && shelves.isEmpty {
                        ProgressView().tint(Theme.Colors.accent)
                            .frame(maxWidth: .infinity).padding(.top, 80)
                    }
                    ForEach(shelves) { shelf in
                        if !shelf.items.isEmpty { row(shelf) }
                    }
                }
                .padding(.vertical, Theme.Spacing.md)
        }
        .background(Theme.Colors.appBackground.ignoresSafeArea())
        .navigationTitle("Anime")
        .navigationDestination(for: CatalogItem.self) { ContentDetailView(item: $0) }
        .task { await load() }
    }

    private func row(_ shelf: AnimeShelf) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(shelf.title)
                .font(Theme.Font.sectionTitle())
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.leading, Theme.Spacing.edge)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.Spacing.md) {
                    ForEach(shelf.items) { item in
                        NavigationLink(value: item) { poster(item) }
                            .buttonStyle(NovaListRowStyle())
                    }
                }
                .padding(.horizontal, Theme.Spacing.edge)
                .padding(.vertical, Theme.Spacing.sm)
            }
        }
    }

    private func poster(_ item: CatalogItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            PosterImage(url: item.posterURL,
                        width: Theme.CardSize.posterWidth,
                        height: Theme.CardSize.posterHeight,
                        title: item.title, year: item.year)
            Text(item.title)
                .font(.appFont(16, weight: .medium))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .frame(width: Theme.CardSize.posterWidth, alignment: .leading)
        }
        .frame(width: Theme.CardSize.posterWidth)
    }

    private func load() async {
        guard !loaded else { return }
        async let popular = env.tmdb.popularAnimeShows()
        async let top = env.tmdb.topRatedAnimeShows()
        async let movies = env.tmdb.popularAnimeMovies()
        async let action = env.tmdb.animeShows(genre: 10759)
        async let comedy = env.tmdb.animeShows(genre: 35)
        async let fantasy = env.tmdb.animeShows(genre: 10765)
        shelves = [
            AnimeShelf(title: "Popular", items: (try? await popular) ?? []),
            AnimeShelf(title: "Top Rated", items: (try? await top) ?? []),
            AnimeShelf(title: "Anime Movies", items: (try? await movies) ?? []),
            AnimeShelf(title: "Action & Adventure", items: (try? await action) ?? []),
            AnimeShelf(title: "Comedy", items: (try? await comedy) ?? []),
            AnimeShelf(title: "Fantasy & Sci-Fi", items: (try? await fantasy) ?? [])
        ]
        loaded = true
    }
}


// MARK: - Airing calendar (tracked shows)
// An auto-updating calendar of the next episode for every series the user is tracking
// (library series, Continue Watching, favorites). Pulls next-episode-to-air from TMDB and
// groups by date. Refreshes on open and on pull-to-refresh.
struct AiringCalendarView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var library: LibraryStore

    private struct Entry: Identifiable {
        let id = UUID(); let title: String; let poster: URL?
        let date: Date; let label: String; let catalog: CatalogItem
    }
    @State private var entries: [Entry] = []
    @State private var loading = false
    @State private var loaded = false

    private static let ymd: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
    private static let dayHeader: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"; return f
    }()

    private var grouped: [(Date, [Entry])] {
        let g = Dictionary(grouping: entries) { Calendar.current.startOfDay(for: $0.date) }
        return g.keys.sorted().map { ($0, g[$0]!.sorted { $0.title < $1.title }) }
    }

    var body: some View {
        Group {
                if loading && entries.isEmpty {
                    ProgressView().tint(Theme.Colors.accent).frame(maxWidth: .infinity).padding(.top, 80)
                } else if entries.isEmpty {
                    VStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "calendar").font(.appFont(44)).foregroundStyle(Theme.Colors.textTertiary)
                        Text("No upcoming episodes")
                            .font(.appFont(20, weight: .semibold)).foregroundStyle(Theme.Colors.textPrimary)
                        Text("Add series to your library or watchlist and their next air dates show up here.")
                            .font(.appFont(15)).foregroundStyle(Theme.Colors.textSecondary)
                            .multilineTextAlignment(.center).padding(.horizontal, Theme.Spacing.xl)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 80)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                            ForEach(grouped, id: \.0) { day, items in
                                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                    Text(Self.dayHeader.string(from: day))
                                        .font(Theme.Font.sectionTitle())
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                        .padding(.leading, Theme.Spacing.edge)
                                    ForEach(items) { e in
                                        NavigationLink(value: e.catalog) { row(e) }
                                            .buttonStyle(NovaListRowStyle())
                                    }
                                }
                            }
                        }
                        .padding(.vertical, Theme.Spacing.md)
                    }
                }
        }
        .background(Theme.Colors.appBackground.ignoresSafeArea())
        .navigationTitle("Calendar")
        .navigationDestination(for: CatalogItem.self) { ContentDetailView(item: $0) }
        .task { await load() }
        .refreshable { loaded = false; await load() }
    }

    private func row(_ e: Entry) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            PosterImage(url: e.poster, width: 58, height: 87, title: e.title)
            VStack(alignment: .leading, spacing: 4) {
                Text(e.title).font(.appFont(17, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary).lineLimit(1)
                Text(e.label).font(.appFont(14))
                    .foregroundStyle(Theme.Colors.textSecondary).lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.edge)
        .contentShape(Rectangle())
    }

    private func trackedSeries() -> [MediaItem] {
        var seen = Set<Int>(); var out: [MediaItem] = []
        for m in (library.continueWatching + library.favorites + library.items) where m.isSeries {
            if let t = m.contentID?.tmdb, seen.insert(t).inserted { out.append(m) }
        }
        return out
    }

    private func load() async {
        guard !loaded else { return }
        loading = true
        let series = trackedSeries()
        let today = Calendar.current.startOfDay(for: Date())
        var built: [Entry] = []
        for m in series {
            guard let tmdb = m.contentID?.tmdb,
                  let next = try? await env.tmdb.nextEpisodeToAir(tmdbID: tmdb),
                  let ds = next.air_date, let d = Self.ymd.date(from: ds), d >= today else { continue }
            var label = String(format: "S%02dE%02d", next.season_number ?? 0, next.episode_number ?? 0)
            if let name = next.name, !name.isEmpty { label += " · \(name)" }
            let cid = m.contentID ?? ContentID(imdb: nil, tmdb: tmdb, trakt: nil, type: .series)
            let catalog = CatalogItem(contentID: cid, title: m.displayTitle, posterURL: m.posterURL)
            built.append(Entry(title: m.displayTitle, poster: m.posterURL, date: d, label: label, catalog: catalog))
        }
        entries = built.sorted { $0.date < $1.date }
        loaded = true; loading = false
    }
}
