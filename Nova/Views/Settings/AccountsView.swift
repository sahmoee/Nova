//
//  AccountsView.swift
//  Nova
//
//  Native settings-style hub for external service accounts and API keys. Account
//  sign-ins are routed through each service's own authorization screen; manual keys
//  live in a separate group so setup does not feel like a credentials form first.
//

import SwiftUI

struct AccountsView: View {
    @Environment(\.openURL) private var openURL

    @State private var tmdbKey = ""
    @State private var openSubtitlesKey = ""
    @State private var omdbKey = ""
    @State private var savedFlash = false

    private let config = AppConfig.shared

    var body: some View {
        SettingsScreen(title: "Accounts") {
            SettingsGroup(
                header: "Services",
                footer: "Sign in through the service's own authorization page. Nova stores account tokens in the device Keychain.",
                rows: serviceRows
            )

            SettingsGroup(
                header: "API Keys",
                footer: "Keys are stored securely in the device Keychain. Leave a field blank to keep its current value.",
                rows: apiKeyRows
            )
        }
        .dismissKeyboardOnTap()
    }

    private var serviceRows: [AnyView] {
        [
            AnyView(
                NavigationLink { TraktConnectView() } label: {
                    SettingsRow(
                        icon: "checkmark.seal.fill",
                        color: Theme.Colors.iconRed,
                        title: "Trakt",
                        detail: traktDetail,
                        status: traktStatusColor
                    )
                }
                .buttonStyle(.plain)
            ),
            AnyView(
                NavigationLink { RealDebridView() } label: {
                    SettingsRow(
                        icon: "arrow.down.circle.fill",
                        color: Theme.Colors.iconRed,
                        title: "Real-Debrid",
                        detail: realDebridDetail,
                        status: realDebridStatusColor
                    )
                }
                .buttonStyle(.plain)
            )
        ]
    }

    private var apiKeyRows: [AnyView] {
        var rows: [AnyView] = [
            AnyView(
                credentialRow(
                    icon: "photo.on.rectangle",
                    color: Theme.Colors.iconGraphite,
                    title: "TMDB",
                    subtitle: "Posters, search, descriptions, seasons, and episodes.",
                    text: $tmdbKey,
                    isPresent: config.isPresent(.tmdbAPIKey),
                    externalURL: "https://www.themoviedb.org/settings/api"
                )
            ),
            AnyView(
                credentialRow(
                    icon: "captions.bubble.fill",
                    color: Theme.Colors.iconSilver,
                    title: "OpenSubtitles",
                    subtitle: "Optional subtitle search provider.",
                    text: $openSubtitlesKey,
                    isPresent: config.isPresent(.openSubtitlesAPIKey),
                    externalURL: "https://www.opensubtitles.com/consumers"
                )
            ),
            AnyView(
                credentialRow(
                    icon: "star.bubble.fill",
                    color: Theme.Colors.iconSilver,
                    title: "OMDb",
                    subtitle: "Optional IMDb, Rotten Tomatoes, and Metacritic ratings.",
                    text: $omdbKey,
                    isPresent: config.isPresent(.omdbAPIKey),
                    externalURL: "https://www.omdbapi.com/apikey.aspx"
                )
            )
        ]

        rows.append(AnyView(saveRow))
        return rows
    }

    private var traktDetail: String {
        if AppConfig.shared.value(for: .traktAccessToken)?.isEmpty == false { return "Connected · Log out" }
        if config.traktClientID?.isEmpty == false && config.traktClientSecret?.isEmpty == false { return "Log in" }
        return "Set up login"
    }

    private var traktStatusColor: Color {
        traktDetail.hasPrefix("Connected") ? Theme.Colors.success : Theme.Colors.textTertiary
    }

    private var realDebridDetail: String {
        KeychainStore.shared.realDebridToken == nil ? "Log in" : "Connected · Log out"
    }

    private var realDebridStatusColor: Color {
        KeychainStore.shared.realDebridToken == nil ? Theme.Colors.textTertiary : Theme.Colors.success
    }

    private func credentialRow(icon: String,
                               color: Color,
                               title: String,
                               subtitle: String,
                               text: Binding<String>,
                               isPresent: Bool,
                               externalURL: String) -> some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
            HStack(alignment: .top, spacing: SettingsMetrics.rowSpacing) {
                SettingsIconTile(systemImage: icon, color: color)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.appFont(SettingsMetrics.title, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        if isPresent {
                            Label("Set", systemImage: "checkmark.circle.fill")
                                .font(.appFont(SettingsMetrics.header, weight: .semibold))
                                .foregroundStyle(Theme.Colors.success)
                        }
                    }
                    Text(subtitle)
                        .font(.appFont(SettingsMetrics.header))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button {
                    if let url = URL(string: externalURL) { openURL(url) }
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.appFont(SettingsMetrics.chevron, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Colors.accent)
                .accessibilityLabel("Open \(title) key page")
            }

            SecureField(isPresent ? "Stored" : "Paste key", text: text)
                .textFieldStyle(.plain)
                .font(.appFont(SettingsMetrics.detail))
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal, SettingsMetrics.rowSpacing)
                .padding(.vertical, SettingsMetrics.rowVPad)
                .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: SettingsMetrics.tileRadius, style: .continuous))
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .textSelection(.enabled)
                #endif
        }
        .padding(.horizontal, SettingsMetrics.rowSpacing + 2)
        .padding(.vertical, SettingsMetrics.rowVPad)
    }

    private var saveRow: some View {
        Button {
            save()
        } label: {
            SettingsRow(
                icon: savedFlash ? "checkmark.circle.fill" : "key.fill",
                color: savedFlash ? .green : .gray,
                title: savedFlash ? "Saved" : "Save API Keys",
                detail: hasInput ? nil : "No changes",
                showsChevron: false,
                tint: hasInput ? nil : Theme.Colors.textTertiary
            )
        }
        .buttonStyle(.plain)
        .disabled(!hasInput)
        .opacity(hasInput ? 1 : 0.65)
    }

    private var hasInput: Bool {
        ![tmdbKey, openSubtitlesKey, omdbKey]
            .allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func save() {
        let tmdb = tmdbKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let openSubtitles = openSubtitlesKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let omdb = omdbKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if !tmdb.isEmpty { config.set(tmdb, for: .tmdbAPIKey) }
        if !openSubtitles.isEmpty { config.set(openSubtitles, for: .openSubtitlesAPIKey) }
        if !omdb.isEmpty { config.set(omdb, for: .omdbAPIKey) }

        tmdbKey = ""
        openSubtitlesKey = ""
        omdbKey = ""
        ToastCenter.shared.show("API keys saved", systemImage: "key.fill")
        savedFlash = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { savedFlash = false }
        }
    }
}
