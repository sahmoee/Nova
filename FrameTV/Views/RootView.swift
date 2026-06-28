//
//  RootView.swift
//  FrameTV
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

    @State private var offerRestore = false
    @State private var showWhatsNew = false
    @State private var reopenItem: MediaItem?

    var body: some View {
        TabView(selection: nav.selectionBinding) {
            HomeView(path: $nav.homePath)
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)

            DiscoverView(path: $nav.discoverPath)
                .tabItem { Label("Discover", systemImage: "magnifyingglass") }
                .tag(AppTab.discover)

            LibraryView(path: $nav.libraryPath)
                .tabItem { Label("Library", systemImage: "rectangle.stack.fill") }
                .tag(AppTab.library)

            SettingsView(path: $nav.settingsPath)
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .environmentObject(nav)
        .environment(\.dynamicAccent, accentManager.accent)
        .tint(accentManager.accent)
        .safeAreaInset(edge: .bottom) {
            nowPlayingBar
        }
        .fullScreenCover(item: $reopenItem) { item in
            PlayerView(item: item)
                .environmentObject(env)
                .environmentObject(nav)
        }
        .toastHost()
        .onAppear(perform: maybeOfferRestore)
        .onAppear(perform: maybeShowWhatsNew)
        .sheet(isPresented: $showWhatsNew) {
            if let note = WhatsNew.note(for: WhatsNewTracker.shared.currentVersion) {
                WhatsNewView(note: note) {
                    WhatsNewTracker.shared.markSeen()
                    showWhatsNew = false
                }
                #if os(iOS)
                .presentationDragIndicator(.visible)
                #endif
            }
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
