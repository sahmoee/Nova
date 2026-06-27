//
//  RealDebridView.swift
//  FrameTV
//
//  Connect a Real-Debrid account by pasting an API token, validate it, and
//  unrestrict a hoster link into a playable item. Token lives in the Keychain.
//  Networking is live (Phase 3); UI is present from the start.
//

import SwiftUI

struct RealDebridView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: SettingsStore

    @State private var tokenText = ""
    @State private var user: RealDebridUser?
    @State private var statusMessage: String?
    @State private var isError = false
    @State private var isWorking = false

    @State private var linkText = ""
    @State private var legalConfirmed = false
    @State private var addedItem: MediaItem?
    @State private var navigate = false

    private var hasToken: Bool { KeychainStore.shared.realDebridToken != nil }

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text("Real-Debrid")
                        .font(Theme.Font.screenTitle())
                        .screenTitleStyle()
                        .foregroundStyle(Theme.Colors.textPrimary)

                    accountSection
                    Divider().overlay(Theme.Colors.separator)
                    unrestrictSection
                }
                .padding(Theme.Spacing.edge)
                .frame(maxWidth: Theme.contentMaxWidth(1100), alignment: .leading)
            }

            NavigationLink(isActive: $navigate) {
                if let addedItem { PlayerView(item: addedItem) }
            } label: { EmptyView() }.hidden()
        }
        .task { await loadAccountIfPossible() }
    }

    // MARK: - Account

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Account")
                .font(Theme.Font.sectionTitle())
                .foregroundStyle(Theme.Colors.textPrimary)

            if let rdUser = user {
                VStack(alignment: .leading, spacing: 8) {
                    Label(rdUser.username, systemImage: "person.fill")
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .font(.appFont(22, weight: .semibold))
                    Label(rdUser.isPremium ? "Premium" : "Free",
                          systemImage: rdUser.isPremium ? "crown.fill" : "person")
                        .foregroundStyle(rdUser.isPremium ? Theme.Colors.warning : Theme.Colors.textSecondary)
                        .font(.appFont(20))
                    if let exp = rdUser.expirationDate {
                        Text("Expires \(exp.formatted(date: .abbreviated, time: .omitted))")
                            .font(.appFont(18))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                FocusableButton(title: "Remove Token", systemImage: "trash") {
                    try? KeychainStore.shared.clearRealDebridToken()
                    user = nil
                    statusMessage = "Token removed."
                    isError = false
                }
                .frame(maxWidth: Theme.isCompact ? .infinity : 300)
            } else {
                Text("Paste your Real-Debrid API token to connect. Get it from your Real-Debrid account settings.")
                    .font(.appFont(20))
                    .foregroundStyle(Theme.Colors.textSecondary)

                SecureField("API token", text: $tokenText)
                    .textFieldStyle(.plain)
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                    .foregroundStyle(Theme.Colors.textPrimary)

                FocusableButton(
                    title: isWorking ? "Validating…" : "Connect",
                    systemImage: "checkmark.circle",
                    prominent: true
                ) {
                    Task { await connect() }
                }
                .frame(maxWidth: Theme.isCompact ? .infinity : 300)
                .disabled(isWorking || tokenText.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let statusMessage {
                Label(statusMessage, systemImage: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(isError ? Theme.Colors.error : Theme.Colors.success)
                    .font(.appFont(20))
            }
        }
    }

    // MARK: - Unrestrict

    private var unrestrictSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Unrestrict a Link")
                .font(Theme.Font.sectionTitle())
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Paste a hoster link you're authorized to access. FrameTV resolves it through your account and adds it to your library.")
                .font(.appFont(20))
                .foregroundStyle(Theme.Colors.textSecondary)

            TextField("https://hoster.example/file", text: $linkText)
                .textFieldStyle(.plain)
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                .foregroundStyle(Theme.Colors.textPrimary)

            if settings.requireLegalConfirmation {
                LegalConfirmToggle(isOn: $legalConfirmed)
            }

            FocusableButton(
                title: isWorking ? "Resolving…" : "Unrestrict & Play",
                systemImage: "play.fill",
                prominent: true
            ) {
                Task { await unrestrict() }
            }
            .frame(maxWidth: Theme.isCompact ? .infinity : 360)
            .disabled(isWorking || !canUnrestrict)
        }
    }

    private var canUnrestrict: Bool {
        guard hasToken, !linkText.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if settings.requireLegalConfirmation { return legalConfirmed }
        return true
    }

    // MARK: - Actions

    private func loadAccountIfPossible() async {
        guard hasToken else { return }
        await connectUsingStoredToken()
    }

    private func connect() async {
        let trimmed = tokenText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        try? KeychainStore.shared.setRealDebridToken(trimmed)
        await connectUsingStoredToken()
        if user != nil { tokenText = "" }
    }

    private func connectUsingStoredToken() async {
        isWorking = true; defer { isWorking = false }
        do {
            let validated = try await environment.realDebrid.validateToken()
            user = validated
            statusMessage = "Connected."
            isError = false
        } catch {
            user = nil
            statusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            isError = true
        }
    }

    private func unrestrict() async {
        isWorking = true; defer { isWorking = false }
        do {
            let result = try await environment.realDebrid.unrestrictLink(linkText)
            guard let url = result.downloadURL else {
                statusMessage = "Real-Debrid didn't return a playable link."
                isError = true
                return
            }
            let item = MediaItem(
                title: result.filename ?? url.lastPathComponent,
                sourceType: .realDebrid,
                playbackURL: url,
                legalAccessConfirmed: legalConfirmed || !settings.requireLegalConfirmation,
                metadata: MetadataParser.parse(filename: result.filename ?? url.lastPathComponent,
                                               fileSize: result.filesize)
            )
            library.add(item)
            addedItem = item
            navigate = true
        } catch {
            statusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            isError = true
        }
    }
}
