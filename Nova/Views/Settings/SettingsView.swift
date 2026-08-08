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
    @State private var sourcesPath = NavigationPath()
    #if os(tvOS)
    @State private var selectedCategory: String = "playback"
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
                    Text("Settings")
                        .font(Theme.Font.screenTitle())
                        .screenTitleStyle()
                        .foregroundStyle(Theme.Colors.textPrimary)
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
        .background(SettingsStyle.groupBackground,
                    in: RoundedRectangle(cornerRadius: SettingsMetrics.groupRadius, style: .continuous))
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
            let items = group.items.filter { $0.title.localizedCaseInsensitiveContains(query) }
            return items.isEmpty ? nil : CategoryGroup(header: group.header, items: items)
        }
    }
    #endif

    // MARK: - tvOS horizontal tabs + panel

    #if os(tvOS)
    private var tvOSBody: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("Settings")
                    .font(Theme.Font.screenTitle())
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.horizontal, Theme.Spacing.edge)
                    .padding(.top, Theme.Spacing.lg)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.md) {
                        ForEach(allCategories) { cat in
                            categoryTab(cat)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.edge)
                    .padding(.vertical, Theme.Spacing.sm)
                }

                // The selected category screen scrolls itself, so it isn't wrapped in
                // another ScrollView here (which would break tvOS focus scrolling).
                selectedDestination
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(Theme.Colors.appBackground.ignoresSafeArea())
        }
    }

    private var selectedDestination: some View {
        (allCategories.first { $0.id == selectedCategory } ?? allCategories[0]).destination()
    }

    private func categoryTab(_ cat: Category) -> some View {
        Button { selectedCategory = cat.id } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: cat.icon)
                Text(cat.title)
            }
            .font(.appFont(22, weight: .semibold))
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(selectedCategory == cat.id ? Theme.Colors.accent : Theme.Colors.card,
                        in: Capsule())
            .foregroundStyle(selectedCategory == cat.id ? Color.white : Theme.Colors.textSecondary)
        }
        .buttonStyle(NovaChipButtonStyle())
        .accessibilityValue(selectedCategory == cat.id ? "Selected" : "")
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
        groups.append(CategoryGroup(items: core))

        // Sources & accounts (hidden in guest mode).
        if !settings.guestMode {
            var accounts: [Category] = [
                Category(id: "sources", icon: "point.3.connected.trianglepath.dotted", color: Theme.Colors.iconSilver,
                         title: "Sources & Health", detail: sourcesHealthDetail, status: sourcesHealthStatusColor) {
                             AnyView(SourcesView(path: self.$sourcesPath))
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
            groups.append(CategoryGroup(header: "Sources & Accounts", items: accounts))
        }

        // Library & home.
        groups.append(CategoryGroup(header: "Content", items: [
            Category(id: "library", icon: "books.vertical.fill", color: Theme.Colors.iconRed, title: "Library") {
                AnyView(SettingsScreen(title: "Library") { LibrarySettingsContent() })
            },
            Category(id: "downloads", icon: "arrow.down.circle.fill", color: Theme.Colors.iconRed,
                     title: "Offline Downloads",
                     detail: "\(env.downloads.downloads.count) items") {
                AnyView(OfflineDownloadsView())
            },
            Category(id: "experience", icon: "appletv.fill", color: Theme.Colors.iconGraphite, title: "Home & Profiles") {
                AnyView(SettingsScreen(title: "Home & Profiles") { ExperienceSettingsContent() })
            },
        ]))

        // Sync & system.
        var system: [Category] = []
        if !settings.guestMode {
            system.append(Category(id: "backup", icon: "icloud.fill", color: Theme.Colors.iconGraphite,
                                   title: "iCloud Backup & Restore", detail: backupDetail) {
                AnyView(BackupView())
            })
        }
        system.append(Category(id: "advanced", icon: "gearshape.2.fill", color: Theme.Colors.iconGraphite, title: "Advanced") {
            AnyView(SettingsScreen(title: "Advanced") { AdvancedSettingsContent() })
        })
        system.append(Category(id: "privacy", icon: "hand.raised.fill", color: Theme.Colors.iconGraphite, title: "Privacy & Legal") {
            AnyView(SettingsScreen(title: "Privacy & Legal") { PrivacyLegalSettingsContent() })
        })
        groups.append(CategoryGroup(header: "System", items: system))

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
        return "Not backed up"
    }
}
