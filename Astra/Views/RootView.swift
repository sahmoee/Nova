//
//  RootView.swift
//  Astra
//
//  Top-level tab navigation. Owns a NavigationCoordinator so that re-tapping the
//  active tab pops its navigation stack back to root (a standard iOS behavior and
//  an easy way to escape any stuck detail/error screen).
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
            .onOpenURL { url in
                // Route frametv:// deep links (Shortcuts, widgets, Top Shelf, QR setup).
                nav.handle(url: url)
            }
            .fullScreenCover(item: $reopenItem) { item in
                PlayerView(item: item)
                    .environmentObject(env)
                    .environmentObject(nav)
            }
            .toastHost()
            .fullScreenCover(isPresented: Binding(
                get: { !hasSeenDisclosure },
                set: { newValue in if !newValue { hasSeenDisclosure = true } }
            )) {
                PersonalMediaDisclosureView {
                    hasSeenDisclosure = true
                }
            }
            .onAppear(perform: maybeOfferRestore)
            .onAppear(perform: autoSyncFromCloud)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    autoSyncFromCloud()
                } else if phase == .background {
                    BackupManager.shared.createBackup()
                }
            }
            .onAppear(perform: maybeShowWhatsNew)
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

    // MARK: - Platform root

    /// All platforms now share the same navigation: a persistent source-list
    /// sidebar (the same one the iPad has always used) with the selected section
    /// in the detail column. iPhone gets it as a slide-over drawer, iPad and Apple
    /// TV as a fixed left rail. This unifies the tab menu across iOS, iPadOS, and
    /// tvOS so every device navigates the same way.
    @ViewBuilder
    private var rootContent: some View {
        #if os(tvOS)
        // tvOS: the sidebar rail is the section switcher. The Menu / TV button is
        // still captured so a pushed detail pops one level before focus returns to
        // the rail; the player owns the button while playing.
        sidebarRoot
            .onExitCommand {
                if nowPlaying.playerPresented {
                    // Player handles its own exit; do nothing here.
                } else if !nav.isAtRoot(nav.selection) {
                    nav.popOne(nav.selection)
                }
                // At a screen root the focus engine returns to the sidebar rail on
                // its own, so there's nothing to summon.
            }
        #else
        sidebarRoot
        #endif
    }

    /// The shared source-list sidebar root (like Files, Music, and the App Store on
    /// iPad) used by iPhone, iPad, and Apple TV. The selected section renders in the
    /// detail column with the Now Playing bar pinned to its bottom.
    @ViewBuilder
    private var sidebarRoot: some View {
        NavigationSplitView(columnVisibility: sidebarColumnVisibility) {
            List(AppTab.allCases, id: \.self, selection: sidebarSelection) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .font(.appFont(19, weight: .medium))
                    .tag(tab)
            }
            .navigationTitle("Astra")
            #if os(iOS)
            .listStyle(.sidebar)
            #endif
        } detail: {
            ZStack(alignment: .bottom) {
                Theme.Colors.appBackground.ignoresSafeArea()
                activeScreen
                    .safeAreaInset(edge: .bottom) { nowPlayingBar }
            }
        }
        .tint(Theme.Colors.accent)
    }

    /// iPad and Apple TV keep both the sidebar and detail visible side-by-side;
    /// iPhone shows the detail full-screen with the sidebar available as a drawer.
    private var sidebarColumnVisibility: Binding<NavigationSplitViewVisibility> {
        #if os(tvOS)
        .constant(.all)
        #else
        .constant(Theme.isPad ? .all : .automatic)
        #endif
    }

    private var sidebarSelection: Binding<AppTab?> {
        Binding(
            get: { nav.selection },
            set: { if let t = $0 {
                // Re-selecting the current section pops it to root, matching the
                // old tab-bar behavior.
                if t == nav.selection {
                    nav.popToRoot(t)
                } else {
                    nav.selection = t
                }
            } }
        )
    }

    /// The active screen for the detail column.
    @ViewBuilder
    private var activeScreen: some View {
        switch nav.selection {
        case .home:     HomeView(path: $nav.homePath)
        case .discover: DiscoverView(path: $nav.discoverPath)
        case .ai:       AIView(path: $nav.aiPath)
        case .library:  LibraryView(path: $nav.libraryPath)
        case .settings: SettingsView(path: $nav.settingsPath)
        }
    }

    /// A "Now Playing" mini-bar shown above the tab bar while something is playing.
    /// Tapping it reopens the player. Only shows when there's a current item and the
    /// player isn't already on screen (the player covers full screen).
    @ViewBuilder
    private var nowPlayingBar: some View {
        if let item = nowPlaying.current, reopenItem == nil, !nowPlaying.playerPresented {
            Button {
                reopenItem = item
            } label: {
                VStack(spacing: 0) {
                    HStack(spacing: Theme.Spacing.sm) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Theme.Colors.card)
                            CachedAsyncImage(url: item.posterURL) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Image(systemName: "film").foregroundStyle(Theme.Colors.textTertiary)
                            }
                        }
                        .frame(width: 40, height: 40)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(.appFont(16, weight: .semibold))
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .lineLimit(1)
                            Text(nowPlaying.isPlaying ? "Now Playing" : "Paused")
                                .font(.appFont(13))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Spacer()
                        Image(systemName: nowPlaying.isPlaying ? "waveform" : "pause.fill")
                            .foregroundStyle(Theme.Colors.accent)
                            .font(.appFont(18, weight: .semibold))
                        Image(systemName: "chevron.up")
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .font(.appFont(13, weight: .semibold))
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)

                    // Thin progress line.
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.white.opacity(0.12))
                            Rectangle().fill(Theme.Colors.accent)
                                .frame(width: geo.size.width * nowPlaying.progress)
                        }
                    }
                    .frame(height: 2)
                }
                .background(.ultraThinMaterial)
            }
            .buttonStyle(.plain)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// Shows the What's New screen once after updating to a version that has a
    /// release note. Defers if a fresh-install restore prompt is showing.
    private func maybeShowWhatsNew() {
        // Don't stack over the first-run restore prompt.
        guard !offerRestore else { return }
        if WhatsNewTracker.shared.shouldShow() {
            showWhatsNew = true
        }
    }

    /// On a fresh install (no prior launch) with an iCloud snapshot present and no
    /// local library yet, offer a one-time restore.
    /// Applies any newer iCloud snapshot from the user's other devices silently so
    /// preferences, sources, and addons follow them across iPhone, iPad, and Apple TV.
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

        // Fresh install: the current version's What's New shouldn't pop (there's
        // nothing "new" relative to a first run), so mark it as already seen.
        WhatsNewTracker.shared.markSeen()

        // Only offer if there's a snapshot and this device looks empty.
        if env.library.items.isEmpty, BackupManager.shared.hasCloudSnapshot() {
            offerRestore = true
        }
    }
}
