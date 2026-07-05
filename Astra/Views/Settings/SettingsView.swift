//
//  SettingsView.swift
//  Astra
//
//  Settings: Real-Debrid account, SMB shares, Playback, Library, Privacy, Legal.
//

import SwiftUI

struct SettingsView: View {
    @Binding var path: NavigationPath
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: SettingsStore

    @State private var confirmClearLibrary = false
    @State private var confirmClearHistory = false
    @State private var expandedSections: [String: Bool] = [:]
    @State private var settingsSearch = ""
    @State private var sourcesPath = NavigationPath()

    /// Summary detail for the Sources & Health row, e.g. "All connected" or
    /// "2 need attention".
    private var sourcesHealthDetail: String {
        let items = SourceHealth.all(addonStore: env.addonStore, smbShareCount: 0)
        let s = SourceHealth.summary(items)
        if s.needsAttention == 0 { return "All connected" }
        return "\(s.needsAttention) need attention"
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.Colors.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        Text("Settings")
                            .font(Theme.Font.screenTitle())
                            .screenTitleStyle()
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .padding(.top, Theme.Spacing.lg)
                            .padding(.horizontal, Theme.Spacing.edge)

                        // Quick filter: type to show only matching sections, all
                        // expanded so results are immediately visible.
                        #if os(iOS)
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(Theme.Colors.textTertiary)
                            TextField("Search settings", text: $settingsSearch)
                                .textFieldStyle(.plain)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .autocorrectionDisabled(true)
                            if !settingsSearch.isEmpty {
                                Button {
                                    settingsSearch = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(Theme.Colors.textTertiary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(Theme.Spacing.md)
                        .refinedCardBackground(cornerRadius: Theme.Radius.button)
                        .padding(.horizontal, Theme.Spacing.edge)
                        #endif

                        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                            // Guest mode hides source setup, advanced streaming, and
                            // account screens on shared devices.
                            if !settings.guestMode {
                                accountsSection
                                streamingSection
                            }
                            playbackSection
                            appearanceSection
                            subtitleSection
                            accessibilitySection
                            librarySection
                            if !settings.guestMode {
                                backupSection
                            }
                            advancedSection
                            privacyLegalSection
                        }
                        // Edge-to-edge accordion: only a slim inset so the section cards
                        // span nearly the full width of the screen.
                        .padding(.horizontal, Theme.isCompact ? Theme.Spacing.sm : Theme.Spacing.edge)
                    }
                    .padding(.bottom, Theme.Spacing.xl)
                    .frame(maxWidth: Theme.contentMaxWidth(1100), alignment: .leading)
                }
            }
            .alert("Clear entire library?", isPresented: $confirmClearLibrary) {
                Button("Clear", role: .destructive) { library.clearAll() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes all saved items. Your sources and credentials stay.")
            }
            .alert("Clear watch history?", isPresented: $confirmClearHistory) {
                Button("Clear", role: .destructive) { library.clearWatchHistory() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This resets resume points and Continue Watching.")
            }
        }
    }

    // MARK: - Sections

    private var accountsSection: some View {
        section("Accounts & Sources") {
            NavigationLink { SetupChecklistView() } label: {
                settingRow("Setup Checklist", systemImage: "checklist",
                           detail: "Get started")
            }.frameRowStyle()
            NavigationLink { SourcesView(path: $sourcesPath) } label: {
                settingRow("Sources & Health", systemImage: "point.3.connected.trianglepath.dotted",
                           detail: sourcesHealthDetail)
            }.frameRowStyle()

            if !settings.reviewSafeMode {
                NavigationLink { RealDebridView() } label: {
                    settingRow("Real-Debrid Account", systemImage: "arrow.down.circle",
                               detail: KeychainStore.shared.realDebridToken == nil ? "Not connected" : "Connected")
                }.frameRowStyle()
            }

            // SMB Shares temporarily hidden while the SMB sign-in issue is sorted out.

            if !settings.reviewSafeMode {
                NavigationLink { AddonsView() } label: {
                    settingRow("Addons", systemImage: "puzzlepiece.extension",
                               detail: "\(env.addonStore.addons.count) installed")
                }.frameRowStyle()
            }

            NavigationLink { DirectURLView() } label: {
                settingRow("Play from URL", systemImage: "link",
                           detail: "Open a direct video link")
            }.frameRowStyle()

            if !settings.reviewSafeMode {
                NavigationLink { MagnetView() } label: {
                    settingRow("Play from Magnet", systemImage: "scope",
                               detail: "Via Real-Debrid")
                }.frameRowStyle()
            }

            NavigationLink { AccountsView() } label: {
                settingRow("Metadata & Accounts", systemImage: "key",
                           detail: "TMDB · Trakt · Subtitles")
            }.frameRowStyle()

            NavigationLink { AISearchSettingsView() } label: {
                settingRow("AI Search", systemImage: "sparkles",
                           detail: AISearchService.isConfigured ? "Ready" : "Set up")
            }.frameRowStyle()
        }
    }

    private var backupSection: some View {
        section("Backup & Sync") {
            NavigationLink { BackupView() } label: {
                settingRow("iCloud Backup & Restore", systemImage: "icloud.and.arrow.up",
                           detail: backupDetail)
            }.frameRowStyle()

            NavigationLink {
                WhatsNewView(note: WhatsNewTracker.shared.currentNote) {}
            } label: {
                settingRow("What's New", systemImage: "sparkles",
                           detail: "Version \(WhatsNewTracker.shared.currentVersion) · Build \(WhatsNewTracker.shared.currentBuild)")
            }.frameRowStyle()
        }
    }

    private var backupDetail: String {
        if let date = BackupManager.shared.lastBackupDate {
            let fmt = DateFormatter(); fmt.dateStyle = .medium; fmt.timeStyle = .short
            return "Last: \(fmt.string(from: date))"
        }
        return "Not backed up"
    }

    private var streamingSection: some View {
        section("Streaming") {
            toggleRow("Auto-Select Best Stream", systemImage: "wand.and.stars",
                      isOn: $settings.autoSelectStream)
            toggleRow("Prefer Cached / Instant Streams", systemImage: "bolt",
                      isOn: $settings.requireCachedStreams)
            toggleRow("Prefer Efficient Codecs (HEVC / AV1)", systemImage: "square.stack.3d.down.right",
                      isOn: $settings.preferEfficientCodec)

            pickerRow("Preferred Quality", systemImage: "4k.tv",
                      selection: $settings.preferredStreamQuality,
                      options: StreamQuality.allCases.filter { $0 != .unknown && $0 != .cam },
                      label: { $0.rawValue })

            pickerRow("Preferred Source", systemImage: "point.3.connected.trianglepath.dotted",
                      selection: $settings.preferredSourceKind,
                      options: SourceKindPreference.allCases,
                      label: { $0.displayName })

            pickerRow("Max File Size", systemImage: "internaldrive",
                      selection: $settings.maxStreamSizeGB,
                      options: [0, 5, 10, 15, 20, 30, 50, 80],
                      label: { $0 == 0 ? "No Limit" : "\($0) GB" })

            pickerRow("Minimum Seeders", systemImage: "person.3",
                      selection: $settings.minSeeders,
                      options: [0, 1, 3, 5, 10, 20, 50],
                      label: { $0 == 0 ? "No Minimum" : "\($0)+" })

            pickerRow("Preferred Audio Language", systemImage: "waveform",
                      selection: $settings.preferredAudioLanguage,
                      options: audioLanguageOptions,
                      label: { audioLanguageLabel($0) })
        }
    }

    /// Language tag options for the preferred-audio picker. Empty string = "Any".
    private var audioLanguageOptions: [String] {
        ["", "EN", "ES", "FR", "DE", "IT", "PT", "JA", "KO", "ZH", "HI", "RU"]
    }

    private func audioLanguageLabel(_ tag: String) -> String {
        guard !tag.isEmpty else { return "Any" }
        let names = ["EN": "English", "ES": "Spanish", "FR": "French", "DE": "German",
                     "IT": "Italian", "PT": "Portuguese", "JA": "Japanese", "KO": "Korean",
                     "ZH": "Chinese", "HI": "Hindi", "RU": "Russian"]
        return names[tag] ?? tag
    }

    /// A labeled menu picker row matching the streaming section styling.
    private func pickerRow<T: Hashable>(_ title: String, systemImage: String,
                                        selection: Binding<T>, options: [T],
                                        label: @escaping (T) -> String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .foregroundStyle(Theme.Colors.textPrimary)
                .font(.appFont(22))
            Spacer()
            Picker("", selection: selection) {
                ForEach(options, id: \.self) { opt in
                    Text(label(opt)).tag(opt)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: Theme.isCompact ? .infinity : 220)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var playbackSection: some View {
        section("Playback") {
            NavigationLink { PlayerSettingsView() } label: {
                settingRow("Player", systemImage: "play.rectangle.on.rectangle",
                           detail: playerDetail)
            }.frameRowStyle()
            toggleRow("Resume Playback", systemImage: "play.circle",
                      isOn: $settings.resumePlaybackEnabled)
            toggleRow("Auto-Play Next Episode", systemImage: "forward.end",
                      isOn: $settings.autoPlayNext)
            toggleRow("Show Skip Intro", systemImage: "forward",
                      isOn: $settings.skipIntroEnabled)
            toggleRow("Automatically Skip Intro", systemImage: "forward.fill",
                      isOn: $settings.autoSkipIntro)
            toggleRow("Show Skip Outro", systemImage: "forward.frame",
                      isOn: $settings.skipOutroEnabled)
            toggleRow("Scrobble to Trakt", systemImage: "checkmark.seal",
                      isOn: $settings.traktScrobblingEnabled)
        }
    }

    private var playerDetail: String {
        #if os(iOS)
        if settings.useExternalPlayer { return settings.preferredExternalPlayer.title }
        #endif
        return settings.builtInPlayer.title
    }

    private var appearanceSection: some View {
        section("Appearance") {
            pickerRow("App Style", systemImage: "paintbrush",
                      selection: $settings.uiStyle,
                      options: UIComponentStyle.allCases) { $0.displayName }
            pickerRow("Home Style", systemImage: "house",
                      selection: $settings.homeStyle,
                      options: HomeStyle.allCases) { $0.displayName }
            pickerRow("Library Style", systemImage: "books.vertical",
                      selection: $settings.libraryStyle,
                      options: LibraryStyle.allCases) { $0.displayName }
            pickerRow("Detail Style", systemImage: "rectangle.portrait.on.rectangle.portrait",
                      selection: $settings.detailStyle,
                      options: DetailStyle.allCases) { $0.displayName }
            #if os(iOS)
            pickerRow("Tab Bar Style", systemImage: "square.bottomthird.inset.filled",
                      selection: $settings.tabBarStyle,
                      options: TabBarStyle.allCases) { $0.displayName }
            #endif
            pickerRow("Search Layout", systemImage: "square.grid.2x2",
                      selection: $settings.searchLayout,
                      options: SearchLayoutStyle.allCases) { $0.displayName }
            pickerRow("VLC Player Overlay", systemImage: "play.rectangle",
                      selection: $settings.vlcOverlayStyle,
                      options: PlayerOverlayStyle.allCases) { $0.displayName }
            Text("The Apple player already uses the native overlay. This controls the look of the VLC player used for MKV and other formats.")
                .font(.appFont(15))
                .foregroundStyle(Theme.Colors.textTertiary)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.xs)
        }
    }

    private var accessibilitySection: some View {
        section("Accessibility") {
            #if os(iOS)
            toggleRow("Respect System Text Size", systemImage: "textformat.size",
                      isOn: $settings.respectSystemTextSize)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Label("Text Size", systemImage: "character.magnify")
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .font(.appFont(22))
                    Spacer()
                    Text("\(Int(settings.textSizeBoost * 100))%")
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .font(.appFont(20))
                        .monospacedDigit()
                }
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "textformat.size.smaller")
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Slider(value: $settings.textSizeBoost, in: 0.8...1.6, step: 0.05)
                        .tint(Theme.Colors.accent)
                    Image(systemName: "textformat.size.larger")
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                if settings.textSizeBoost != 1.0 {
                    Button("Reset to 100%") { settings.textSizeBoost = 1.0 }
                        .font(.appFont(16))
                        .foregroundStyle(Theme.Colors.accent)
                }
                Text("Adjusts Astra's text. Turn on Respect System Text Size to also follow your device's Display & Text Size setting. Changes apply as you move between screens.")
                    .font(.appFont(15))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            #else
            Text("Text size follows the living-room layout on Apple TV. Adjust text size on iPhone or iPad in Settings ▸ Accessibility.")
                .font(.appFont(20))
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            #endif
        }
    }

    private var subtitleSection: some View {
        section("Subtitles") {
            toggleRow("Enable Subtitles", systemImage: "captions.bubble",
                      isOn: $settings.subtitlesEnabled)
            HStack {
                Label("Preferred Language", systemImage: "globe")
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .font(.appFont(22))
                Spacer()
                Picker("", selection: $settings.subtitleLanguage) {
                    ForEach(Self.subtitleLanguages, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: Theme.isCompact ? .infinity : 240)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
    }

    private static let subtitleLanguages: [(String, String)] = [
        ("en", "English"), ("es", "Spanish"), ("fr", "French"), ("de", "German"),
        ("it", "Italian"), ("pt", "Portuguese"), ("ru", "Russian"), ("ja", "Japanese"),
        ("ko", "Korean"), ("zh", "Chinese"), ("ar", "Arabic"), ("nl", "Dutch")
    ]

    private var librarySection: some View {
        section("Library") {
            NavigationLink { LibraryFoldersView() } label: {
                settingRow("Library Folders", systemImage: "folder.badge.plus", detail: "Add folders to scan")
            }.frameRowStyle()
            NavigationLink { LibraryEnrichView() } label: {
                settingRow("Clean Up Library", systemImage: "wand.and.stars", detail: "Titles & images")
            }.frameRowStyle()
            NavigationLink { LibraryQualityView() } label: {
                settingRow("Library Health", systemImage: "checkmark.seal", detail: "Scan & fix")
            }.frameRowStyle()
            NavigationLink { DuplicatesView() } label: {
                settingRow("Duplicate Cleanup", systemImage: "arrow.triangle.merge",
                           detail: duplicateCountDetail)
            }.frameRowStyle()
            toggleRow("Safe Mode", systemImage: "exclamationmark.shield",
                      isOn: $settings.safeMode)
            if settings.safeMode {
                Text("Safe Mode is on. Addons, AI search, and external sources are disabled so the app loads quickly. Turn it off once things are stable.")
                    .font(.appFont(15))
                    .foregroundStyle(Theme.Colors.warning)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.sm)
            }
            actionRow("Clear Watch History", systemImage: "clock.arrow.circlepath",
                      tint: Theme.Colors.warning) { confirmClearHistory = true }
            actionRow("Clear Library", systemImage: "trash",
                      tint: Theme.Colors.error) { confirmClearLibrary = true }
        }
    }

    /// Detail string for the Duplicate Cleanup row.
    private var duplicateCountDetail: String {
        let n = library.duplicateGroups().count
        return n == 0 ? "None found" : "\(n) to review"
    }

    private var privacyLegalSection: some View {
        section("Privacy & Legal") {
            toggleRow("Require Legal Confirmation", systemImage: "checkmark.shield",
                      isOn: $settings.requireLegalConfirmation)
            NavigationLink { PrivacyLegalView() } label: {
                settingRow("Privacy & Legal Info", systemImage: "hand.raised", detail: "View")
            }.frameRowStyle()
        }
    }

    private var advancedSection: some View {
        section("Advanced") {
            NavigationLink { GuestModeView() } label: {
                settingRow("Guest Mode", systemImage: "person.2",
                           detail: settings.guestMode ? "On" : "Off")
            }.frameRowStyle()
            if !settings.guestMode {
                NavigationLink { DebugReportView() } label: {
                    settingRow("Debug Report", systemImage: "ladybug", detail: "Export")
                }.frameRowStyle()
            }
        }
    }

    // MARK: - Builders

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        // Build the section's body once so it isn't captured by DisclosureGroup's
        // escaping closure (which would require `content` to be @escaping).
        let body = VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            content()
        }
        let query = settingsSearch.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty && !title.localizedCaseInsensitiveContains(query) {
            EmptyView()
        } else {
        #if os(iOS)
        // Expandable accordion. Starts expanded; the user can collapse sections.
        DisclosureGroup(
            isExpanded: Binding(
                get: {
                    if !settingsSearch.trimmingCharacters(in: .whitespaces).isEmpty { return true }
                    return expandedSections[title] ?? defaultExpanded(title)
                },
                set: { expandedSections[title] = $0 }
            )
        ) {
            body.padding(.top, Theme.Spacing.sm)
        } label: {
            Text(title)
                .font(Theme.Font.sectionTitle())
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .tint(Theme.Colors.textSecondary)
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        #else
        // tvOS: keep sections always visible (DisclosureGroup isn't focus-friendly).
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Font.sectionTitle())
                .foregroundStyle(Theme.Colors.textPrimary)
            body
        }
        #endif
        }
    }

    /// Sections that start expanded; others start collapsed to keep Settings tidy.
    /// While a search is active, every matching section is expanded so results are
    /// immediately visible.
    private func defaultExpanded(_ title: String) -> Bool {
        if !settingsSearch.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        return ["Accounts & Sources", "Backup & Sync"].contains(title)
    }

    private func settingRow(_ title: String, systemImage: String, detail: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .foregroundStyle(Theme.Colors.textPrimary)
                .font(.appFont(22))
            Spacer()
            Text(detail).foregroundStyle(Theme.Colors.textSecondary).font(.appFont(20))
            Image(systemName: "chevron.right").foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(.vertical, Theme.Spacing.xs)
        .contentShape(Rectangle())
    }

    private func toggleRow(_ title: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(Theme.Colors.textPrimary)
                .font(.appFont(22))
        }
        .tint(Theme.Colors.accent)
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func actionRow(_ title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(tint)
                    .font(.appFont(22))
                Spacer()
            }
            .padding(.vertical, Theme.Spacing.xs)
            .contentShape(Rectangle())
        }
        .frameRowStyle()
    }
}
