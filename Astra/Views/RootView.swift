//
//  RootView.swift
//  Astra
//
//  Top-level navigation. Owns a NavigationCoordinator so that re-selecting the
//  active section pops its navigation stack back to root (an easy way to escape any
//  stuck detail/error screen).
//
//  iPad keeps its persistent NavigationSplitView sidebar. iPhone and Apple TV use a
//  shared pop-up menu (MenuOverlay) that slides over the current screen instead of
//  switching to a separate screen. On iPhone a small floating Menu button summons
//  it; on tvOS the Menu / TV button summons it.
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
    @State private var showMenu = false
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
                // Seamless resume from the Now Playing bar: same stream, same
                // position, no Resume/Restart prompt.
                PlayerView(item: item, autoResume: true)
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

    // MARK: - Shared menu plumbing

    /// A binding that both switches sections and pops the current section to root
    /// when re-selected. Used by the pop-up menu on iPhone and tvOS.
    private var menuSelection: Binding<AppTab> {
        Binding(
            get: { nav.selection },
            set: { newValue in
                if newValue == nav.selection {
                    nav.popToRoot(newValue)
                } else {
                    nav.selection = newValue
                }
            }
        )
    }

    private var menuIsOpen: Bool { showMenu && !nowPlaying.playerPresented }

    // MARK: - Platform root

    #if os(tvOS)
    /// tvOS: the active screen is shown full-screen. The Menu / TV button summons the
    /// shared pop-up menu to switch sections. While a video plays, Menu is handled by
    /// the player, not here.
    @ViewBuilder
    private var rootContent: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()

            activeScreen
                .ignoresSafeArea(.container, edges: .bottom)
                // While the menu is up, take the underlying screen out of the focus
                // engine so remote swipes can't move items behind it.
                .disabled(menuIsOpen)
                .accessibilityHidden(menuIsOpen)

            if menuIsOpen {
                MenuOverlay(selection: menuSelection, onDismiss: {
                    withAnimation(.easeOut(duration: 0.2)) { showMenu = false }
                }, onSelect: { tab in
                    // Always land on the section's main screen: pop its stack to root,
                    // then switch to it.
                    nav.popToRoot(tab)
                    nav.selection = tab
                })
                .transition(.opacity)
                .zIndex(10)
            }
        }
        // Capture the Menu / TV button. Priority: if the menu is open, close it; if a
        // detail screen is pushed, go back one level; otherwise (at a screen root)
        // summon the section menu. The player owns the button while playing.
        .onExitCommand {
            if showMenu {
                withAnimation(.easeOut(duration: 0.2)) { showMenu = false }
            } else if nowPlaying.playerPresented {
                // Player handles its own exit; do nothing here.
            } else if !nav.isAtRoot(nav.selection) {
                nav.popOne(nav.selection)
            } else {
                withAnimation(.easeOut(duration: 0.2)) { showMenu = true }
            }
        }
        .overlay(alignment: .bottom) { nowPlayingBar }
    }

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
        // Re-inject the shared environment objects here so every section — and every
        // destination pushed inside its NavigationStack (Sources ▸ Addons, Settings ▸
        // Addons, etc.) — reliably sees AppEnvironment. On iPad the NavigationSplitView
        // detail column is a separate environment branch, so without this a pushed
        // AddonsView could crash with "No ObservableObject of type AppEnvironment".
        .environmentObject(env)
        .environmentObject(env.library)
        .environmentObject(env.progress)
        .environmentObject(settings)
    }
    #else
    /// iOS / iPadOS. iPad keeps its persistent sidebar; iPhone uses the pop-up menu.
    @ViewBuilder
    private var rootContent: some View {
        if Theme.isPad {
            iPadSidebarRoot
        } else {
            iPhoneMenuRoot
        }
    }

    /// iPad-specific root: a persistent source-list sidebar (like Files, Music, and
    /// the App Store on iPad) with the selected section in the detail column.
    /// Unchanged from before.
    @ViewBuilder
    private var iPadSidebarRoot: some View {
        NavigationSplitView {
            List(AppTab.allCases, id: \.self, selection: sidebarSelection) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .font(.appFont(19, weight: .medium))
                    .tag(tab)
            }
            .navigationTitle("Astra")
            .listStyle(.sidebar)
        } detail: {
            ZStack(alignment: .bottom) {
                Theme.Colors.appBackground.ignoresSafeArea()
                activeScreen
                    .safeAreaInset(edge: .bottom) { nowPlayingBar }
            }
        }
        .tint(Theme.Colors.accent)
    }

    private var sidebarSelection: Binding<AppTab?> {
        Binding(
            get: { nav.selection },
            set: { if let t = $0 { nav.selection = t } }
        )
    }

    /// iPhone root: the active screen fills the window. A small floating Menu button
    /// summons the shared pop-up menu; tapping the backdrop dismisses it.
    @ViewBuilder
    private var iPhoneMenuRoot: some View {
        ZStack(alignment: .bottomLeading) {
            Theme.Colors.appBackground.ignoresSafeArea()

            activeScreen
                // Reserve bottom space so scroll content rests above the floating menu
                // button — and above the taller stack when the persistent Now Playing
                // bar is also showing. Collapses to nothing while the player is up.
                .safeAreaInset(edge: .bottom) {
                    let hasBar = nowPlaying.current != nil && !nowPlaying.playerPresented
                    Color.clear.frame(height: nowPlaying.playerPresented
                                      ? 0
                                      : (hasBar ? Theme.scaled(132, min: 112) : Theme.scaled(64, min: 52)))
                }
                .disabled(menuIsOpen)
                .accessibilityHidden(menuIsOpen)

            // Now Playing bar + floating Menu button stack at the bottom.
            VStack(alignment: .leading, spacing: 0) {
                nowPlayingBar
                if !nowPlaying.playerPresented {
                    MenuButton {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            showMenu = true
                        }
                    }
                    .padding(.leading, Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.sm)
                }
            }

            if menuIsOpen {
                MenuOverlay(selection: menuSelection, onDismiss: {
                    withAnimation(.easeOut(duration: 0.2)) { showMenu = false }
                }, onSelect: { tab in
                    // Always land on the section's main screen: pop its stack to root,
                    // then switch to it.
                    nav.popToRoot(tab)
                    nav.selection = tab
                })
                .transition(.opacity)
                .zIndex(10)
            }
        }
    }

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
        // Re-inject the shared environment objects here so every section — and every
        // destination pushed inside its NavigationStack (Sources ▸ Addons, Settings ▸
        // Addons, etc.) — reliably sees AppEnvironment. On iPad the NavigationSplitView
        // detail column is a separate environment branch, so without this a pushed
        // AddonsView could crash with "No ObservableObject of type AppEnvironment".
        .environmentObject(env)
        .environmentObject(env.library)
        .environmentObject(env.progress)
        .environmentObject(settings)
    }
    #endif

    /// A "Now Playing" mini-bar shown while something is playing. Tapping it reopens
    /// the player. Only shows when there's a current item and the player isn't already
    /// on screen (the player covers full screen).
    @ViewBuilder
    private var nowPlayingBar: some View {
        if let item = nowPlaying.current, reopenItem == nil, !nowPlaying.playerPresented {
            VStack(spacing: 0) {
                HStack(spacing: Theme.Spacing.sm) {
                    // Tapping this area (poster + titles + resume glyph) reopens the
                    // player and resumes. Kept as a tap area — not a Button — so the
                    // Stop button beside it stays independently tappable on every
                    // platform (nested Buttons are unreliable, especially on tvOS).
                    Button {
                        reopenItem = item
                    } label: {
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
                                Text("Paused · Tap to resume")
                                    .font(.appFont(13))
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            Spacer(minLength: Theme.Spacing.sm)
                            Image(systemName: "chevron.up")
                                .foregroundStyle(Theme.Colors.textTertiary)
                                .font(.appFont(13, weight: .semibold))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // Play / Resume: playback pauses when you leave the player, so this
                    // reopens the player and resumes from the saved position.
                    Button {
                        reopenItem = item
                    } label: {
                        Image(systemName: "play.fill")
                            .foregroundStyle(Theme.Colors.accent)
                            .font(.appFont(24, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Resume")

                    // Explicit Stop: fully ends the session and dismisses the bar.
                    // The bar otherwise persists until stop or app close, by design.
                    Button {
                        withAnimation { nowPlaying.clear() }
                    } label: {
                        Image(systemName: "stop.fill")
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .font(.appFont(22, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stop")
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
