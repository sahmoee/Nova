//
//  AccountsView.swift
//  FrameTV
//
//  Metadata & account credentials. Lets the user enter a TMDB API key, Trakt
//  client id/secret (then connect via device code), and an OpenSubtitles key.
//  Values are stored in the Keychain; a FrameTVConfig.json file can supply fallbacks.
//

import SwiftUI

struct AccountsView: View {
    @EnvironmentObject private var env: AppEnvironment

    @State private var tmdbKey = ""
    @State private var traktID = ""
    @State private var traktSecret = ""
    @State private var openSubtitlesKey = ""
    @State private var savedFlash = false

    private let config = AppConfig.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("Metadata & Accounts")
                    .font(Theme.Font.screenTitle())
                    .screenTitleStyle()
                    .foregroundStyle(Theme.Colors.textPrimary)

                credentialField(
                    title: "TMDB API Key",
                    subtitle: "Powers search, posters, and episode data. Free from themoviedb.org.",
                    text: $tmdbKey,
                    isPresent: config.isPresent(.tmdbAPIKey)
                )

                Divider().overlay(Theme.Colors.card)

                Text("Trakt")
                    .font(Theme.Font.sectionTitle())
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Sync your watchlist and watched progress. Create an app at trakt.tv/oauth/applications.")
                    .font(.appFont(18))
                    .foregroundStyle(Theme.Colors.textSecondary)

                credentialField(title: "Trakt Client ID", subtitle: nil,
                                text: $traktID, isPresent: config.isPresent(.traktClientID))
                credentialField(title: "Trakt Client Secret", subtitle: nil,
                                text: $traktSecret, isPresent: config.isPresent(.traktClientSecret), secure: true)

                NavigationLink {
                    TraktConnectView()
                } label: {
                    HStack {
                        Label("Connect Trakt Account", systemImage: "checkmark.seal")
                            .font(.appFont(22, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.Colors.textTertiary)
                    }
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                }
                .buttonStyle(.plain)

                Divider().overlay(Theme.Colors.card)

                credentialField(
                    title: "OpenSubtitles API Key",
                    subtitle: "Optional. Enables subtitle search from OpenSubtitles.",
                    text: $openSubtitlesKey,
                    isPresent: config.isPresent(.openSubtitlesAPIKey)
                )

                FocusableButton(title: savedFlash ? "Saved ✓" : "Save Credentials",
                                systemImage: "checkmark.circle",
                                prominent: true) {
                    save()
                }
                .frame(maxWidth: Theme.isCompact ? .infinity : 360)
                .padding(.top, Theme.Spacing.md)

                Text("Credentials are stored securely in the device Keychain.")
                    .font(.appFont(16))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(Theme.Spacing.edge)
            .frame(maxWidth: Theme.contentMaxWidth(1100), alignment: .leading)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .onAppear(perform: loadExisting)
    }

    private func credentialField(title: String,
                                 subtitle: String?,
                                 text: Binding<String>,
                                 isPresent: Bool,
                                 secure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(title)
                    .font(.appFont(22, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                if isPresent {
                    Label("Set", systemImage: "checkmark.circle.fill")
                        .font(.appFont(16))
                        .foregroundStyle(Theme.Colors.success)
                }
            }
            if let subtitle {
                Text(subtitle)
                    .font(.appFont(16))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Group {
                if secure {
                    SecureField(isPresent ? "•••••••• (stored)" : "Enter value", text: text)
                } else {
                    TextField(isPresent ? "•••••••• (stored)" : "Enter value", text: text)
                }
            }
            .textFieldStyle(.plain)
            .font(.appFont(20))
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            #if os(iOS)
            .autocapitalization(.none)
            .disableAutocorrection(true)
            #endif
        }
    }

    private func loadExisting() {
        // We don't echo secrets back; fields stay blank unless the user types.
    }

    private func save() {
        if !tmdbKey.isEmpty { config.set(tmdbKey, for: .tmdbAPIKey) }
        if !traktID.isEmpty { config.set(traktID, for: .traktClientID) }
        if !traktSecret.isEmpty { config.set(traktSecret, for: .traktClientSecret) }
        if !openSubtitlesKey.isEmpty { config.set(openSubtitlesKey, for: .openSubtitlesAPIKey) }

        tmdbKey = ""; traktID = ""; traktSecret = ""; openSubtitlesKey = ""
        savedFlash = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { savedFlash = false }
        }
    }
}
