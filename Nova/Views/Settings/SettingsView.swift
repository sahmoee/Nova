//
//  SettingsView.swift
//  Nova
//
//  The Settings home. On iOS/iPadOS it's an Apple-Settings-style directory: grouped
//  rounded cards of rows, each with a colored icon tile, that push into a category
//  screen. On tvOS it's a horizontal strip of category tabs with the selected
//  category's controls filling the panel below.
//

import SwiftUI

struct SettingsView: View {
    @Binding var path: NavigationPath
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: SettingsStore

    @State private var settingsSearch = ""
    #if os(tvOS)
    @State private var selectedCategory: String = "icloud"
    #endif

    // MARK: - Directory model

    /// A single directory entry: how it looks in the list plus the screen it opens.
    private struct Category: Identifiable {
        let id: String
        let icon: String
        let color: Color
        let title: String
        var detail: String? = nil
        var status: Color? = nil
        let destination: () -> AnyView
    }

    private struct CategoryGroup: Identifiable {
        let id = UUID()
        var header: String? = nil
        let items: [Category]
    }

    var body: some View {
        #if os(tvOS)
        tvOSBody
        #else
        iOSBody
        #endif
    }

    // MARK: - iOS / iPadOS directory

    #if !os(tvOS)
    private var iOSBody: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    CinematicPageHeader(title: "Settings",
                                        subtitle: "Playback, sources, accounts, and Nova",
                                        systemImage: "gearshape.fill")
                        .padding(.top, Theme.Spacing.md)

                    searchField

                    if filteredGroups.isEmpty {
                        EmptyStateView(
                            systemImage: "magnifyingglass",
                            title: "No settings found",
                            message: "Try a broader search term."
                        )
                        .frame(minHeight: 280)
                    } else {
                        ForEach(filteredGroups) { group in
                            SettingsGroup(header: group.header, rows: group.items.map { rowLink(for: $0) })
                        }
                    }
                }
                .padding(.horizontal, Theme.isCompact ? Theme.Spacing.md : Theme.Spacing.edge)
                .padding(.bottom, Theme.Spacing.xl)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.Colors.appBackground.ignoresSafeArea())
        }
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.Colors.textTertiary)
            TextField("Search", text: $settingsSearch)
                .textFieldStyle(.plain)
                .font(.appFont(SettingsMetrics.title))
                .foregroundStyle(Theme.Colors.textPrimary)
                .autocorrectionDisabled(true)
            if !settingsSearch.isEmpty {
                Button { settingsSearch = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear settings search")
            }
        }
        .padding(.horizontal, SettingsMetrics.rowSpacing + 2)
        .padding(.vertical, SettingsMetrics.rowVPad)
        .cinematicGlass(radius: SettingsMetrics.groupRadius)
    }

    private func rowLink(for cat: Category) -> AnyView {
        AnyView(
            NavigationLink { cat.destination() } label: {
                SettingsRow(icon: cat.icon, color: cat.color, title: cat.title,
                            detail: cat.detail, status: cat.status)
            }
            .buttonStyle(.plain)
        )
    }

    /// Groups filtered by the search query (matched against the row titles).
    private var filteredGroups: [CategoryGroup] {
        let query = settingsSearch.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return directoryGroups }
        return directoryGroups.compactMap { group in
            let items = group.items.filter {
                [$0.title, $0.detail ?? "", $0.id]
                    .contains { $0.localizedCaseInsensitiveContains(query) }
            }
            return items.isEmpty ? nil : CategoryGroup(header: group.header, items: items)
        }
    }
    #endif

    // MARK: - tvOS horizontal tabs + panel

    #if os(tvOS)
    private var tvOSBody: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: 18) {
                TVPageHeading(title: "Settings", systemImage: "gearshape.fill")
                    .padding(.horizontal, TVReferenceStyle.edge)
                    .padding(.top, TVReferenceStyle.top)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(tvCategories) { cat in
                            categoryTab(cat)
                        }
                    }
                    .padding(.horizontal, TVReferenceStyle.edge)
                    .padding(.vertical, 6)
                }

                // The selected category screen scrolls itself, so it isn't wrapped in
                // another ScrollView here (which would break tvOS focus scrolling).
                selectedDestination
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(Theme.Colors.appBackground.ignoresSafeArea())
            .tvRootMenu()
        }
    }

    private var selectedDestination: some View {
        (tvCategories.first { $0.id == selectedCategory } ?? tvCategories[0]).destination()
    }

    private func categoryTab(_ cat: Category) -> some View {
        Button { selectedCategory = cat.id } label: {
            Text(cat.title)
                .font(.appFont(22, weight: .semibold))
                .padding(.horizontal, 17)
                .frame(height: TVReferenceStyle.controlHeight)
        }
        .buttonStyle(TVReferenceButtonStyle(selected: selectedCategory == cat.id))
        .accessibilityValue(selectedCategory == cat.id ? "Selected" : "")
    }

    private var tvCategories: [Category] {
        func tab(_ id: String, _ title: String, _ destination: @escaping () -> AnyView) -> Category {
            Category(id: id, icon: "gearshape", color: Theme.Colors.accent, title: title, destination: destination)
        }
        var tabs: [Category] = []
        if !settings.guestMode {
            tabs.append(tab("sources", "Sources") { AnyView(SourcesView()) })
            if !settings.reviewSafeMode {
                tabs.append(tab("addons", "Addons") { AnyView(AddonsView()) })
            }
        }
        tabs.append(tab("player", "Player") { AnyView(TVPlayerSettingsPanel()) })
        if !settings.guestMode {
            tabs.append(tab("mdblist", "MDBList") { AnyView(TVIntegrationSettingsPanel(kind: .mdblist)) })
            tabs.append(tab("trakt", "Trakt") { AnyView(TVIntegrationSettingsPanel(kind: .trakt)) })
        }
        tabs.append(tab("regex", "Regex") { AnyView(TitleCleanupRulesView()) })
        tabs.append(tab("autoplay", "Auto-Play") { AnyView(TVAutoPlaySettingsPanel()) })
        tabs.append(tab("cache", "Cache") { AnyView(TVCacheSettingsPanel()) })
        tabs.append(tab("search", "Search") { AnyView(TVSearchSettingsPanel()) })
        tabs.append(tab("ui", "UI") { AnyView(TVInterfaceSettingsPanel()) })
        tabs.append(tab("glow", "Glow") { AnyView(TVIntegrationSettingsPanel(kind: .glow)) })
        tabs.append(tab("legal", "Legal") { AnyView(SettingsScreen(title: "Legal") { PrivacyLegalSettingsContent() }) })
        if !settings.guestMode {
            tabs.append(tab("icloud", "iCloud") { AnyView(TVCloudSettingsPanel(addonStore: env.addonStore)) })
            tabs.append(tab("web", "Web Management") { AnyView(TVWebManagementPanel()) })
        }
        return tabs
    }
    #endif

    // MARK: - Categories

    /// Every category, flat. iOS arranges these into the grouped directory; tvOS uses
    /// them as horizontal tabs.
    private var allCategories: [Category] {
        directoryGroups.flatMap(\.items)
    }

    private var directoryGroups: [CategoryGroup] {
        var groups: [CategoryGroup] = []

        // Experience & playback.
        var core: [Category] = [
            Category(id: "playback", icon: "play.rectangle.on.rectangle", color: Theme.Colors.iconRed,
                     title: "Playback", detail: playerDetail) {
                         AnyView(SettingsScreen(title: "Playback") { PlaybackSettingsContent() })
                     },
        ]
        if !settings.guestMode {
            core.append(Category(id: "streaming", icon: "dot.radiowaves.left.and.right",
                                 color: Theme.Colors.iconRed, title: "Streaming") {
                AnyView(SettingsScreen(title: "Streaming") { StreamingSettingsContent() })
            })
        }
        core.append(Category(id: "appearance", icon: "paintbrush.fill", color: Theme.Colors.iconRed, title: "Appearance") {
            AnyView(SettingsScreen(title: "Appearance") { AppearanceSettingsContent() })
        })
        core.append(Category(id: "subtitles", icon: "captions.bubble.fill", color: Theme.Colors.iconSilver, title: "Subtitles") {
            AnyView(SettingsScreen(title: "Subtitles") { SubtitleSettingsContent() })
        })
        core.append(Category(id: "accessibility", icon: "accessibility", color: Theme.Colors.iconGraphite, title: "Accessibility") {
            AnyView(SettingsScreen(title: "Accessibility") { AccessibilitySettingsContent() })
        })
        groups.append(CategoryGroup(header: "Playback & Display", items: core))

        // Sources & accounts (hidden in guest mode).
        if !settings.guestMode {
            var accounts: [Category] = [
                Category(id: "sources", icon: "point.3.connected.trianglepath.dotted", color: Theme.Colors.iconSilver,
                         title: "Sources & Health", detail: sourcesHealthDetail, status: sourcesHealthStatusColor) {
                             AnyView(SourcesView())
                         },
            ]
            accounts.append(Category(id: "accounts", icon: "person.crop.circle.badge.checkmark", color: Theme.Colors.iconGraphite,
                                     title: "Accounts", detail: accountsDetail, status: accountsStatusColor) {
                AnyView(AccountsView())
            })
            if !settings.reviewSafeMode {
                accounts.append(Category(id: "addons", icon: "puzzlepiece.extension.fill", color: Theme.Colors.iconRed,
                                         title: "Add-ons", detail: "\(env.addonStore.addons.count) installed") {
                    AnyView(AddonsView())
                })
            }
            accounts.append(Category(id: "aisearch", icon: "sparkles", color: Theme.Colors.iconRed, title: "AI Search",
                                     detail: AISearchService.isConfigured ? "Ready" : "Set up",
                                     status: AISearchService.isConfigured ? Theme.Colors.success : Theme.Colors.warning) {
                AnyView(AISearchSettingsView())
            })
            accounts.append(Category(id: "playlink", icon: "link", color: Theme.Colors.iconGraphite, title: "Play from Link") {
                AnyView(PlayFromLinkView())
            })
            accounts.append(Category(id: "setup", icon: "checklist", color: Theme.Colors.iconSilver, title: "Setup Checklist") {
                AnyView(SetupChecklistView())
            })
            groups.append(CategoryGroup(header: "Connections", items: accounts))
        }

        // Library & home.
        groups.append(CategoryGroup(header: "Library", items: [
            Category(id: "library", icon: "books.vertical.fill", color: Theme.Colors.iconRed, title: "Library") {
                AnyView(SettingsScreen(title: "Library") { LibrarySettingsContent() })
            },
            Category(id: "downloads", icon: "arrow.down.circle.fill", color: Theme.Colors.iconRed,
                     title: "Offline Downloads",
                     detail: "\(env.downloads.downloads.count) items") {
                AnyView(OfflineDownloadsView())
            },
            Category(id: "library-folders", icon: "externaldrive.connected.to.line.below", color: Theme.Colors.iconSilver,
                     title: "SMB Library Folders", detail: "\(env.libraryFolders.folders.count) configured") {
                AnyView(LibraryFoldersView())
            },
            Category(id: "experience", icon: "appletv.fill", color: Theme.Colors.iconGraphite, title: "Home & Profiles") {
                AnyView(SettingsScreen(title: "Home & Profiles") { ExperienceSettingsContent() })
            },
        ]))

        groups.append(CategoryGroup(header: "Testing", items: [
            Category(id: "qa", icon: "checkmark.seal.fill", color: Theme.Colors.iconGraphite,
                     title: "Quality Assurance", detail: "Off by default") {
                AnyView(UnifiedQASettingsView())
            }
        ]))

        // Sync & system.
        var system: [Category] = []
        if !settings.guestMode {
            system.append(Category(id: "backup", icon: "icloud.fill", color: Theme.Colors.iconGraphite,
                                   title: "iCloud Sync & Backup", detail: backupDetail) {
                AnyView(BackupView())
            })
        }
        system.append(Category(id: "advanced", icon: "gearshape.2.fill", color: Theme.Colors.iconGraphite, title: "Advanced") {
            AnyView(SettingsScreen(title: "Advanced") { AdvancedSettingsContent() })
        })
        system.append(Category(id: "privacy", icon: "hand.raised.fill", color: Theme.Colors.iconGraphite, title: "Privacy & Legal") {
            AnyView(SettingsScreen(title: "Privacy & Legal") { PrivacyLegalSettingsContent() })
        })
        groups.append(CategoryGroup(header: "Data & Support", items: system))

        return groups
    }

    // MARK: - Row detail values

    private var playerDetail: String {
        #if os(iOS)
        if settings.useExternalPlayer { return settings.preferredExternalPlayer.title }
        #endif
        return settings.builtInPlayer.title
    }

    private var sourcesHealthDetail: String {
        let items = SourceHealth.all(addonStore: env.addonStore, smbShareCount: 0)
        let s = SourceHealth.summary(items)
        return s.needsAttention == 0 ? "All connected" : "\(s.needsAttention) need attention"
    }

    private var sourcesHealthStatusColor: Color {
        let items = SourceHealth.all(addonStore: env.addonStore, smbShareCount: 0)
        return SourceHealth.summary(items).needsAttention == 0 ? Theme.Colors.success : Theme.Colors.warning
    }

    private var accountsDetail: String {
        let connectedCount = [
            AppConfig.shared.value(for: .traktAccessToken)?.isEmpty == false,
            KeychainStore.shared.realDebridToken != nil
        ].filter { $0 }.count
        return connectedCount == 0 ? "Set up" : "\(connectedCount) connected"
    }

    private var accountsStatusColor: Color {
        accountsDetail == "Set up" ? Theme.Colors.textTertiary : Theme.Colors.success
    }

    private var backupDetail: String {
        if let date = BackupManager.shared.lastBackupDate {
            return "Last: \(date.mediumDateTimeText)"
        }
        return "Settings, profiles, keys & add-ons"
    }
}
