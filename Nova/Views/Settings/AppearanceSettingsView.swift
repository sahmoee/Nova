//
//  AppearanceSettingsView.swift
//  Nova
//
//  Omni-style layout options: card size, titles, Continue Watching size, hero
//  behavior, the tvOS sidebar style and a high-contrast focus ring. Values live in
//  `@AppStorage` under `OmniLayoutKey` so every screen reads the same settings.
//

import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage(OmniLayoutKey.posterSize) private var posterSize = OmniPosterSize.medium.rawValue
    @AppStorage(OmniLayoutKey.alwaysShowTitles) private var alwaysShowTitles = false
    @AppStorage(OmniLayoutKey.smallContinueWatching) private var smallContinueWatching = false
    @AppStorage(OmniLayoutKey.highContrastFocus) private var highContrastFocus = false
    @AppStorage(OmniLayoutKey.sidebarStyle) private var sidebarStyle = OmniSidebarStyle.rail.rawValue
    @AppStorage(OmniLayoutKey.heroAutoAdvance) private var heroAutoAdvance = true
    @AppStorage(OmniLayoutKey.showHeroLogo) private var showHeroLogo = true

    var body: some View {
        Form {
            Section {
                Picker("Card Size", selection: $posterSize) {
                    ForEach(OmniPosterSize.allCases) { Text($0.title).tag($0.rawValue) }
                }
                #if os(tvOS)
                Toggle("Always Show Titles", isOn: $alwaysShowTitles)
                #endif
                Toggle("Compact Continue Watching", isOn: $smallContinueWatching)
            } header: {
                Text("Rows")
            } footer: {
                Text("Each catalog can also use poster or landscape cards in Settings › Experience › Catalogs.")
            }

            Section("Featured Hero") {
                Toggle("Rotate Featured Titles", isOn: $heroAutoAdvance)
                Toggle("Show Title Logos", isOn: $showHeroLogo)
            }

            #if os(tvOS)
            Section {
                Picker("Sidebar", selection: $sidebarStyle) {
                    ForEach(OmniSidebarStyle.allCases) { Text($0.title).tag($0.rawValue) }
                }
            } footer: {
                Text("Press Back on any main page to open the sidebar.")
            }
            #endif

            Section {
                Toggle("High-Contrast Focus", isOn: $highContrastFocus)
            } footer: {
                Text("Adds a solid white outline to the focused poster or card.")
            }
        }
        .navigationTitle("Appearance")
    }
}
