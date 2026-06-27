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
    @EnvironmentObject private var env: AppEnvironment

    @State private var offerRestore = false

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

            SourcesView(path: $nav.sourcesPath)
                .tabItem { Label("Sources", systemImage: "antenna.radiowaves.left.and.right") }
                .tag(AppTab.sources)

            SettingsView(path: $nav.settingsPath)
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .environmentObject(nav)
        .toastHost()
        .onAppear(perform: maybeOfferRestore)
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

    /// On a fresh install (no prior launch) with an iCloud snapshot present and no
    /// local library yet, offer a one-time restore.
    private func maybeOfferRestore() {
        let defaults = UserDefaults.standard
        let launchedKey = "app.hasLaunchedBefore"
        guard !defaults.bool(forKey: launchedKey) else { return }
        defaults.set(true, forKey: launchedKey)

        // Only offer if there's a snapshot and this device looks empty.
        if env.library.items.isEmpty, BackupManager.shared.hasCloudSnapshot() {
            offerRestore = true
        }
    }
}
