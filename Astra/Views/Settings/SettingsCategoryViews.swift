//
//  SettingsCategoryViews.swift
//  Astra
//
//  The individual Settings categories, extracted from the old single-screen Settings
//  into focused sub-screens. Each exposes a `*Content` view (just the grouped rows)
//  so it can be pushed as its own screen on iOS/iPadOS or rendered inside the tvOS
//  horizontal-tabs panel, without duplicating the controls.
//

import SwiftUI

// MARK: - Playback

struct PlaybackSettingsContent: View {
    @EnvironmentObject private var settings: SettingsStore

    private var playerDetail: String {
        #if os(iOS)
        if settings.useExternalPlayer { return settings.preferredExternalPlayer.title }
        #endif
        return settings.builtInPlayer.title
    }

    var body: some View {
        Group {
            SettingsGroup(rows: [
                AnyView(
                    NavigationLink { PlayerSettingsView() } label: {
                        SettingsRow(icon: "play.rectangle.on.rectangle", color: .purple,
                                    title: "Player", detail: playerDetail)
                    }.buttonStyle(.plain)
                )
            ])
            SettingsGroup(header: "Playback", rows: [
                AnyView(SettingsToggleRow(icon: "play.circle", color: .green,
                                          title: "Resume Playback", isOn: $settings.resumePlaybackEnabled)),
                AnyView(SettingsToggleRow(icon: "forward.end", color: .blue,
                                          title: "Auto-Play Next Episode", isOn: $settings.autoPlayNext)),
                AnyView(SettingsToggleRow(icon: "forward", color: .orange,
                                          title: "Show Skip Intro", isOn: $settings.skipIntroEnabled)),
                AnyView(SettingsToggleRow(icon: "forward.fill", color: .orange,
                                          title: "Automatically Skip Intro", isOn: $settings.autoSkipIntro)),
                AnyView(SettingsToggleRow(icon: "forward.frame", color: .orange,
                                          title: "Show Skip Outro", isOn: $settings.skipOutroEnabled)),
                AnyView(SettingsToggleRow(icon: "checkmark.seal", color: .red,
                                          title: "Scrobble to Trakt", isOn: $settings.traktScrobblingEnabled)),
            ])
        }
    }
}

// MARK: - Streaming

struct StreamingSettingsContent: View {
    @EnvironmentObject private var settings: SettingsStore

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

    var body: some View {
        Group {
            SettingsGroup(rows: [
                AnyView(SettingsToggleRow(icon: "wand.and.stars", color: .indigo,
                                          title: "Auto-Select Best Stream", isOn: $settings.autoSelectStream)),
                AnyView(SettingsToggleRow(icon: "bolt", color: .yellow,
                                          title: "Prefer Cached / Instant", isOn: $settings.requireCachedStreams)),
                AnyView(SettingsToggleRow(icon: "square.stack.3d.down.right", color: .teal,
                                          title: "Prefer Efficient Codecs", isOn: $settings.preferEfficientCodec)),
            ])

            SettingsGroup(header: "Preferences", rows: [
                AnyView(SettingsPickerRow(icon: "4k.tv", color: .orange, title: "Preferred Quality",
                                          selection: $settings.preferredStreamQuality,
                                          options: StreamQuality.allCases.filter { $0 != .unknown && $0 != .cam },
                                          label: { $0.rawValue })),
                AnyView(SettingsPickerRow(icon: "point.3.connected.trianglepath.dotted", color: .green,
                                          title: "Preferred Source",
                                          selection: $settings.preferredSourceKind,
                                          options: SourceKindPreference.allCases,
                                          label: { $0.displayName })),
                AnyView(SettingsPickerRow(icon: "internaldrive", color: .gray, title: "Max File Size",
                                          selection: $settings.maxStreamSizeGB,
                                          options: [0, 5, 10, 15, 20, 30, 50, 80],
                                          label: { $0 == 0 ? "No Limit" : "\($0) GB" })),
                AnyView(SettingsPickerRow(icon: "person.3", color: .blue, title: "Minimum Seeders",
                                          selection: $settings.minSeeders,
                                          options: [0, 1, 3, 5, 10, 20, 50],
                                          label: { $0 == 0 ? "No Minimum" : "\($0)+" })),
                AnyView(SettingsPickerRow(icon: "waveform", color: .pink, title: "Preferred Audio",
                                          selection: $settings.preferredAudioLanguage,
                                          options: audioLanguageOptions,
                                          label: { audioLanguageLabel($0) })),
            ])

            sourcePriorityGroup
        }
    }

    // MARK: Source priority

    private var sourcePriorityGroup: some View {
        let kinds: [SourceKind] = [.cloud, .torrent, .localSMB, .directURL]
        let current = settings.sourceKindPriority.compactMap(SourceKind.init(rawValue:))
        let combined = current.isEmpty ? kinds : current + kinds.filter { !current.contains($0) }
        var seen = Set<SourceKind>()
        let ordered = combined.filter { seen.insert($0).inserted }
        return SettingsGroup(
            header: "Source Priority",
            footer: "Streams from higher sources rank first when quality is comparable.",
            rows: ordered.enumerated().map { index, kind in
                AnyView(sourcePriorityRow(index: index, kind: kind, count: ordered.count, ordered: ordered))
            }
        )
    }

    private func sourcePriorityRow(index: Int, kind: SourceKind, count: Int, ordered: [SourceKind]) -> some View {
        HStack(spacing: SettingsMetrics.rowSpacing) {
            Text("\(index + 1)")
                .font(.system(size: SettingsMetrics.detail, weight: .bold))
                .foregroundStyle(Theme.Colors.textTertiary)
                .frame(width: SettingsMetrics.tile, height: SettingsMetrics.tile)
                .background(Color(white: 0.17),
                            in: RoundedRectangle(cornerRadius: SettingsMetrics.tileRadius, style: .continuous))
            Text(sourceKindLabel(kind))
                .font(.system(size: SettingsMetrics.title))
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer(minLength: 8)
            Button { move(kind, up: true, in: ordered) } label: {
                Image(systemName: "chevron.up").font(.system(size: SettingsMetrics.chevron, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(index == 0 ? Theme.Colors.textTertiary : Theme.Colors.accent)
            .disabled(index == 0)
            Button { move(kind, up: false, in: ordered) } label: {
                Image(systemName: "chevron.down").font(.system(size: SettingsMetrics.chevron, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(index == count - 1 ? Theme.Colors.textTertiary : Theme.Colors.accent)
            .disabled(index == count - 1)
        }
        .padding(.horizontal, SettingsMetrics.rowSpacing + 2)
        .padding(.vertical, SettingsMetrics.rowVPad * 0.7)
    }

    private func sourceKindLabel(_ kind: SourceKind) -> String {
        switch kind {
        case .cloud:     return "Cloud (Debrid)"
        case .torrent:   return "Torrent"
        case .localSMB:  return "SMB / Local"
        case .directURL: return "Direct URL"
        case .liveTV:    return "Live TV"
        case .unknown:   return "Other"
        }
    }

    private func move(_ kind: SourceKind, up: Bool, in ordered: [SourceKind]) {
        var list = ordered
        guard let idx = list.firstIndex(of: kind) else { return }
        let target = up ? idx - 1 : idx + 1
        guard list.indices.contains(target) else { return }
        list.swapAt(idx, target)
        settings.sourceKindPriority = list.map(\.rawValue)
    }
}

// MARK: - Appearance

struct AppearanceSettingsContent: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Group {
            SettingsGroup(rows: appearanceRows)
            SettingsGroup(footer: "The Apple player already uses the native overlay. This controls the look of the VLC player used for MKV and other formats.",
                          rows: [
                AnyView(SettingsPickerRow(icon: "play.rectangle", color: .purple, title: "VLC Player Overlay",
                                          selection: $settings.vlcOverlayStyle,
                                          options: PlayerOverlayStyle.allCases,
                                          label: { $0.displayName })),
            ])
        }
    }

    private var appearanceRows: [AnyView] {
        var rows: [AnyView] = [
            AnyView(SettingsPickerRow(icon: "paintbrush", color: .pink, title: "App Style",
                                      selection: $settings.uiStyle, options: UIComponentStyle.allCases,
                                      label: { $0.displayName })),
            AnyView(SettingsPickerRow(icon: "house", color: .orange, title: "Home Style",
                                      selection: $settings.homeStyle, options: HomeStyle.allCases,
                                      label: { $0.displayName })),
            AnyView(SettingsPickerRow(icon: "books.vertical", color: .brown, title: "Library Style",
                                      selection: $settings.libraryStyle, options: LibraryStyle.allCases,
                                      label: { $0.displayName })),
            AnyView(SettingsPickerRow(icon: "rectangle.portrait.on.rectangle.portrait", color: .blue,
                                      title: "Detail Style", selection: $settings.detailStyle,
                                      options: DetailStyle.allCases, label: { $0.displayName })),
        ]
        #if os(iOS)
        rows.append(AnyView(SettingsPickerRow(icon: "square.bottomthird.inset.filled", color: .indigo,
                                              title: "Tab Bar Style", selection: $settings.tabBarStyle,
                                              options: TabBarStyle.allCases, label: { $0.displayName })))
        #endif
        rows.append(AnyView(SettingsPickerRow(icon: "square.grid.2x2", color: .teal, title: "Search Layout",
                                              selection: $settings.searchLayout,
                                              options: SearchLayoutStyle.allCases, label: { $0.displayName })))
        return rows
    }
}

// MARK: - Subtitles

struct SubtitleSettingsContent: View {
    @EnvironmentObject private var settings: SettingsStore

    private static let languages: [(String, String)] = [
        ("en", "English"), ("es", "Spanish"), ("fr", "French"), ("de", "German"),
        ("it", "Italian"), ("pt", "Portuguese"), ("ru", "Russian"), ("ja", "Japanese"),
        ("ko", "Korean"), ("zh", "Chinese"), ("ar", "Arabic"), ("nl", "Dutch")
    ]

    var body: some View {
        Group {
            SettingsGroup(rows: enableRows)
            SettingsGroup(rows: [
                AnyView(SettingsPickerRow(icon: "globe", color: .blue, title: "Preferred Language",
                                          selection: $settings.subtitleLanguage,
                                          options: Self.languages.map(\.0),
                                          label: { code in Self.languages.first { $0.0 == code }?.1 ?? code })),
            ])
        }
    }

    private var enableRows: [AnyView] {
        var rows: [AnyView] = [
            AnyView(SettingsToggleRow(icon: "captions.bubble", color: .teal,
                                      title: "Enable Subtitles", isOn: $settings.subtitlesEnabled)),
        ]
        if settings.subtitlesEnabled {
            rows.append(AnyView(SettingsToggleRow(icon: "arrow.down.circle", color: .blue,
                                                  title: "Auto-Download from Add-ons",
                                                  isOn: $settings.autoDownloadSubtitles)))
            rows.append(AnyView(SettingsNote("When playback starts, Astra searches enabled subtitle providers and automatically uses your preferred language. You can also search manually from the player subtitle picker.")))
        }
        return rows
    }
}

// MARK: - Accessibility

struct AccessibilitySettingsContent: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Group {
            #if os(iOS)
            SettingsGroup(rows: [
                AnyView(SettingsToggleRow(icon: "textformat.size", color: .blue,
                                          title: "Respect System Text Size", isOn: $settings.respectSystemTextSize)),
            ])
            SettingsGroup(footer: "Adjusts Astra's text. Turn on Respect System Text Size to also follow your device's Display & Text Size setting. Changes apply as you move between screens.",
                          rows: [AnyView(textSizeRow)])
            #else
            SettingsGroup(rows: [
                AnyView(SettingsNote("Text size follows the living-room layout on Apple TV. Adjust text size on iPhone or iPad in Settings ▸ Accessibility.",
                                     tint: Theme.Colors.textSecondary)),
            ])
            #endif
        }
    }

    #if os(iOS)
    private var textSizeRow: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing * 0.7) {
            HStack {
                Label("Text Size", systemImage: "character.magnify")
                    .font(.system(size: SettingsMetrics.title))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Text("\(Int(settings.textSizeBoost * 100))%")
                    .font(.system(size: SettingsMetrics.detail))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .monospacedDigit()
            }
            HStack(spacing: SettingsMetrics.rowSpacing) {
                Image(systemName: "textformat.size.smaller").foregroundStyle(Theme.Colors.textSecondary)
                Slider(value: $settings.textSizeBoost, in: 0.8...1.6, step: 0.05).tint(Theme.Colors.accent)
                Image(systemName: "textformat.size.larger").foregroundStyle(Theme.Colors.textSecondary)
            }
            if settings.textSizeBoost != 1.0 {
                Button("Reset to 100%") { settings.textSizeBoost = 1.0 }
                    .font(.system(size: SettingsMetrics.detail))
                    .foregroundStyle(Theme.Colors.accent)
            }
        }
        .padding(.horizontal, SettingsMetrics.rowSpacing + 2)
        .padding(.vertical, SettingsMetrics.rowVPad)
    }
    #endif
}

// MARK: - Apple TV Experience

struct ExperienceSettingsContent: View {
    @StateObject private var profiles = ViewingProfileStore.shared

    private func experienceBinding(_ keyPath: WritableKeyPath<AppleTVExperiencePreferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { profiles.preferences[keyPath: keyPath] },
            set: { value in profiles.preferences[keyPath: keyPath] = value }
        )
    }

    private var platformSymbol: String {
        switch PlatformCapabilities.platform {
        case .iPhone: return "iphone"
        case .iPad:   return "ipad"
        case .appleTV: return "appletv.fill"
        }
    }

    var body: some View {
        Group {
            SettingsGroup(rows: [
                AnyView(
                    NavigationLink { ViewingProfileSwitcherView(store: profiles) } label: {
                        SettingsRow(icon: "person.2.circle", color: .teal, title: "Viewing Profiles",
                                    detail: profiles.activeProfile.name)
                    }.buttonStyle(.plain)
                )
            ])
            SettingsGroup(header: "Home Rows", rows: [
                AnyView(SettingsToggleRow(icon: "rectangle.on.rectangle.angled", color: .purple,
                                          title: "Auto-Advance Featured", isOn: experienceBinding(\.autoAdvanceHero))),
                AnyView(SettingsToggleRow(icon: "square.grid.2x2", color: .blue,
                                          title: "Quick Access Row", isOn: experienceBinding(\.showQuickAccess))),
                AnyView(SettingsToggleRow(icon: "point.3.connected.trianglepath.dotted", color: .green,
                                          title: "Source Health on Home", isOn: experienceBinding(\.showSourceHub))),
                AnyView(SettingsToggleRow(icon: "sparkles.rectangle.stack", color: .indigo,
                                          title: "Smart Collections", isOn: experienceBinding(\.showSmartCollections))),
                AnyView(SettingsToggleRow(icon: "clock.arrow.circlepath", color: .orange,
                                          title: "Watch History Rail", isOn: experienceBinding(\.showWatchHistory))),
                AnyView(SettingsToggleRow(icon: "wand.and.stars", color: .pink,
                                          title: "Because You Watched", isOn: experienceBinding(\.showBecauseYouWatched))),
                AnyView(SettingsToggleRow(icon: "figure.walk.motion", color: .mint,
                                          title: "Reduce Artwork Motion", isOn: experienceBinding(\.reduceArtworkMotion))),
            ])
            SettingsGroup(rows: [
                AnyView(SettingsRow(icon: platformSymbol, color: .gray, title: "This Device",
                                    detail: PlatformCapabilities.platform.displayName, showsChevron: false)),
            ])
        }
    }
}

// MARK: - Library

struct LibrarySettingsContent: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var library: LibraryStore
    @State private var confirmClearLibrary = false
    @State private var confirmClearHistory = false

    private var duplicateCountDetail: String {
        let n = library.duplicateGroups().count
        return n == 0 ? "None found" : "\(n) to review"
    }

    var body: some View {
        Group {
            SettingsGroup(rows: [
                AnyView(
                    NavigationLink { LibraryHealthView() } label: {
                        SettingsRow(icon: "checkmark.seal", color: .green, title: "Library Health",
                                    detail: duplicateCountDetail)
                    }.buttonStyle(.plain)
                ),
                AnyView(
                    NavigationLink { LibraryEnrichView() } label: {
                        SettingsRow(icon: "wand.and.stars", color: .indigo, title: "Clean Up Library (AI)")
                    }.buttonStyle(.plain)
                ),
            ])
            SettingsGroup(rows: safeModeRows)
            SettingsGroup(rows: [
                AnyView(
                    Button { confirmClearHistory = true } label: {
                        SettingsRow(icon: "clock.arrow.circlepath", color: .orange,
                                    title: "Clear Watch History", showsChevron: false, tint: Theme.Colors.warning)
                    }.buttonStyle(.plain)
                ),
                AnyView(
                    Button { confirmClearLibrary = true } label: {
                        SettingsRow(icon: "trash", color: .red, title: "Clear Library",
                                    showsChevron: false, tint: Theme.Colors.error)
                    }.buttonStyle(.plain)
                ),
            ])
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

    private var safeModeRows: [AnyView] {
        var rows: [AnyView] = [
            AnyView(SettingsToggleRow(icon: "exclamationmark.shield", color: .orange,
                                      title: "Safe Mode", isOn: $settings.safeMode)),
        ]
        if settings.safeMode {
            rows.append(AnyView(SettingsNote("Safe Mode is on. Addons, AI search, and external sources are disabled so the app loads quickly. Turn it off once things are stable.",
                                             tint: Theme.Colors.warning)))
        }
        return rows
    }
}

// MARK: - Advanced

struct AdvancedSettingsContent: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Group {
            SettingsGroup(rows: advancedRows)
        }
    }

    private var advancedRows: [AnyView] {
        var rows: [AnyView] = [
            AnyView(
                NavigationLink { GuestModeView() } label: {
                    SettingsRow(icon: "person.2", color: .gray, title: "Guest Mode",
                                detail: settings.guestMode ? "On" : "Off")
                }.buttonStyle(.plain)
            ),
        ]
        if !settings.guestMode {
            rows.append(AnyView(
                NavigationLink { DebugReportView() } label: {
                    SettingsRow(icon: "ladybug", color: .red, title: "Debug Report", detail: "Export")
                }.buttonStyle(.plain)
            ))
        }
        return rows
    }
}

// MARK: - Privacy & Legal

struct PrivacyLegalSettingsContent: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Group {
            SettingsGroup(rows: [
                AnyView(
                    NavigationLink {
                        WhatsNewView(note: WhatsNewTracker.shared.currentNote) {}
                    } label: {
                        SettingsRow(icon: "sparkles", color: .yellow, title: "What's New",
                                    detail: "v\(WhatsNewTracker.shared.currentVersion)")
                    }.buttonStyle(.plain)
                ),
                AnyView(SettingsToggleRow(icon: "checkmark.shield", color: .green,
                                          title: "Require Legal Confirmation",
                                          isOn: $settings.requireLegalConfirmation)),
                AnyView(
                    NavigationLink { PrivacyLegalView() } label: {
                        SettingsRow(icon: "hand.raised", color: .gray, title: "Privacy & Legal Info")
                    }.buttonStyle(.plain)
                ),
            ])
        }
    }
}
