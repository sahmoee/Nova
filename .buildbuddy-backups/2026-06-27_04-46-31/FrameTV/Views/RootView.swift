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
    }
}
