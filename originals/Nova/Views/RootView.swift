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

    var body: some View {
        rootContent
            .environmentObject(nav)
            .environment(\.dynamicAccent, accentManager.accent)
            .tint(accentManager.accent)
            .onOpenURL { nav.handle(url: $0) }
            .fullScreenCover(item: $reopenItem) { item in
                PlayerView(item: item, autoResume: true)
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
        switch PlatformCapabilities.navigationStyle {
        case .sidebar:
            iPadSidebarRoot
        case .bottomTabs, .televisionTabs:
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

            AIView(path: $nav.aiPath)
                .tabItem { Label(AppTab.ai.title, systemImage: AppTab.ai.systemImage) }
                .tag(AppTab.ai)

            LibraryView(path: $nav.libraryPath)
                .tabItem { Label(AppTab.library.title, systemImage: AppTab.library.systemImage) }
                .tag(AppTab.library)

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
            case .ai:       AIView(path: $nav.aiPath)
            case .library:  LibraryView(path: $nav.libraryPath)
            case .settings: SettingsView(path: $nav.settingsPath)
            }
        }
        .environmentObject(env)
        .environmentObject(env.library)
        .environmentObject(env.progress)
        .environmentObject(settings)
    }

    // MARK: - Now Playing mini-player

    @ViewBuilder
    private var nowPlayingBar: some View {
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
                            }
                            Spacer(minLength: Theme.Spacing.sm)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button { reopenItem = item } label: {
                        Image(systemName: "play.fill")
                            .font(.appFont(isTV ? 24 : 18, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(width: isTV ? 58 : 42, height: isTV ? 58 : 42)
                            .background(.white, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Resume playback")

                    Button { withAnimation { nowPlaying.clear() } } label: {
                        Image(systemName: "xmark")
                            .font(.appFont(isTV ? 21 : 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.76))
                            .frame(width: isTV ? 50 : 38, height: isTV ? 50 : 38)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close Now Playing")
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
                .frame(height: isTV ? 5 : 3)
                .padding(.horizontal, isTV ? Theme.Spacing.md : 12)
                .padding(.bottom, isTV ? 12 : 8)
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
