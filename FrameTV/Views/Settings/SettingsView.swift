//
//  SettingsView.swift
//  FrameTV
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

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        Text("Settings")
                            .font(Theme.Font.screenTitle())
                            .screenTitleStyle()
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .padding(.top, Theme.Spacing.lg)

                        accountsSection
                        streamingSection
                        playbackSection
                        subtitleSection
                        librarySection
                        privacyLegalSection
                    }
                    .padding(.horizontal, Theme.Spacing.edge)
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
            NavigationLink { RealDebridView() } label: {
                settingRow("Real-Debrid Account", systemImage: "arrow.down.circle",
                           detail: KeychainStore.shared.realDebridToken == nil ? "Not connected" : "Connected")
            }.buttonStyle(.plain)

            NavigationLink { SMBListView() } label: {
                settingRow("SMB Shares", systemImage: "externaldrive.connected.to.line.below",
                           detail: "Manage")
            }.buttonStyle(.plain)

            NavigationLink { AddonsView() } label: {
                settingRow("Addons", systemImage: "puzzlepiece.extension",
                           detail: "\(env.addonStore.addons.count) installed")
            }.buttonStyle(.plain)

            NavigationLink { AccountsView() } label: {
                settingRow("Metadata & Accounts", systemImage: "key",
                           detail: "TMDB · Trakt · Subtitles")
            }.buttonStyle(.plain)
        }
    }

    private var streamingSection: some View {
        section("Streaming") {
            toggleRow("Auto-Select Best Stream", systemImage: "wand.and.stars",
                      isOn: $settings.autoSelectStream)
            toggleRow("Prefer Cached / Instant Streams", systemImage: "bolt",
                      isOn: $settings.requireCachedStreams)
            HStack {
                Label("Preferred Quality", systemImage: "4k.tv")
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .font(.appFont(22))
                Spacer()
                Picker("", selection: $settings.preferredStreamQuality) {
                    ForEach(StreamQuality.allCases.filter { $0 != .unknown && $0 != .cam }, id: \.self) { q in
                        Text(q.rawValue).tag(q)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: Theme.isCompact ? .infinity : 200)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
    }

    private var playbackSection: some View {
        section("Playback") {
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
            actionRow("Clear Watch History", systemImage: "clock.arrow.circlepath",
                      tint: Theme.Colors.warning) { confirmClearHistory = true }
            actionRow("Clear Library", systemImage: "trash",
                      tint: Theme.Colors.error) { confirmClearLibrary = true }
        }
    }

    private var privacyLegalSection: some View {
        section("Privacy & Legal") {
            toggleRow("Require Legal Confirmation", systemImage: "checkmark.shield",
                      isOn: $settings.requireLegalConfirmation)
            NavigationLink { PrivacyLegalView() } label: {
                settingRow("Privacy & Legal Info", systemImage: "hand.raised", detail: "View")
            }.buttonStyle(.plain)
        }
    }

    // MARK: - Builders

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Font.sectionTitle())
                .foregroundStyle(Theme.Colors.textPrimary)
            content()
        }
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
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
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
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
