//
//  RealDebridView.swift
//  Nova
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

    // Browser device-code flow.
    @State private var rdDeviceCode: RDDeviceCode?
    @State private var rdPollTask: Task<Void, Never>?
    @Environment(\.openURL) private var openURL

    @State private var linkText = ""
    @State private var legalConfirmed = false
    @State private var addedItem: MediaItem?
    // Confirms sign-out before the token is actually deleted.
    @State private var confirmingRemoveToken = false
    @State private var showingTokenFallback = false

    private var hasToken: Bool { KeychainStore.shared.realDebridToken != nil }

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text("Real-Debrid")
                        .font(Theme.Font.screenTitle())
                        .screenTitleStyle()
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("Connect your own Real-Debrid account to resolve links to media you own or are authorized to access. Nova does not provide or index any content.")
                        .font(.appFont(17))
                        .foregroundStyle(Theme.Colors.textSecondary)

                    accountSection
                    Divider().overlay(Theme.Colors.separator)
                    unrestrictSection
                }
                .padding(Theme.Spacing.edge)
                .frame(maxWidth: Theme.contentMaxWidth(1100), alignment: .leading)
            }
        }
        .fullScreenCover(item: $addedItem) { item in
            // Present the player as a full-screen cover so no tab bar, sidebar,
            // or mini-bar remains visible during playback on any platform.
            NavigationStack { PlayerView(item: item) }
        }
        .task { await loadAccountIfPossible() }
        .dismissKeyboardOnTap()
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
                    // Ask first — removing the token signs the account out.
                    confirmingRemoveToken = true
                }
                .frame(maxWidth: Theme.isCompact ? .infinity : 300)
                .alert("Remove Real-Debrid Token?", isPresented: $confirmingRemoveToken) {
                    Button("Remove", role: .destructive) {
                        try? KeychainStore.shared.clearRealDebridToken()
                        user = nil
                        statusMessage = "Token removed."
                        isError = false
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("You'll be signed out of Real-Debrid on this device until you connect again.")
                }
            } else if let device = rdDeviceCode {
                // Browser device-code flow in progress.
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Text("Sign in to Real-Debrid")
                        .font(.appFont(22, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Your code:")
                        .font(.appFont(17))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text(device.userCode)
                        .font(.appFont(48, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .tracking(6)
                    FocusableButton(title: "Open Real-Debrid to Sign In",
                                    systemImage: "arrow.up.right.square", prominent: true) {
                        openRDAuth(device)
                    }
                    .frame(maxWidth: Theme.isCompact ? .infinity : 340)
                    Text("After you approve in Real-Debrid, come back here — it connects automatically.")
                        .font(.appFont(15))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    HStack(spacing: Theme.Spacing.sm) {
                        ProgressView().tint(Theme.Colors.accent)
                        Text("Waiting for authorization…")
                            .font(.appFont(17))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    Button("Cancel") { cancelRDDeviceFlow() }
                        .font(.appFont(16))
                        .foregroundStyle(Theme.Colors.accent)
                }
            } else {
                Text("Sign in with your Real-Debrid account, or paste an API token.")
                    .font(.appFont(20))
                    .foregroundStyle(Theme.Colors.textSecondary)

                FocusableButton(title: "Sign in with Real-Debrid",
                                systemImage: "person.crop.circle.badge.checkmark",
                                prominent: true) {
                    Task { await startRDDeviceFlow() }
                }
                .frame(maxWidth: Theme.isCompact ? .infinity : 340)

                DisclosureGroup("Use API token", isExpanded: $showingTokenFallback) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        SecureField("API token", text: $tokenText)
                            .textFieldStyle(.plain)
                            .padding(Theme.Spacing.md)
                            .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                            .foregroundStyle(Theme.Colors.textPrimary)

                        FocusableButton(
                            title: isWorking ? "Validating…" : "Connect with Token",
                            systemImage: "checkmark.circle"
                        ) {
                            Task { await connect() }
                        }
                        .frame(maxWidth: Theme.isCompact ? .infinity : 300)
                        .disabled(isWorking || tokenText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.top, Theme.Spacing.sm)
                }
                .font(.appFont(16, weight: .semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
                .tint(Theme.Colors.accent)
                .padding(.top, Theme.Spacing.sm)
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
            Text("Paste a hoster link you're authorized to access. Nova resolves it through your account and adds it to your library.")
                .font(.appFont(20))
                .foregroundStyle(Theme.Colors.textSecondary)

            HStack(spacing: Theme.Spacing.sm) {
                TextField("https://hoster.example/file", text: $linkText)
                    .textFieldStyle(.plain)
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .textSelection(.enabled)
                    #endif
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                    .foregroundStyle(Theme.Colors.textPrimary)
                #if os(iOS)
                PasteButton(text: $linkText)
                #endif
            }

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

    // MARK: - Browser device-code flow

    private func startRDDeviceFlow() async {
        do {
            let device = try await environment.realDebrid.requestDeviceCode()
            rdDeviceCode = device
            startRDPolling(device)
        } catch {
            statusMessage = "Couldn't start sign-in. Try again."
            isError = true
        }
    }

    private func openRDAuth(_ device: RDDeviceCode) {
        let urlString = device.verificationURL.isEmpty
            ? "https://real-debrid.com/device" : device.verificationURL
        if let url = URL(string: urlString) { openURL(url) }
    }

    private func startRDPolling(_ device: RDDeviceCode) {
        rdPollTask?.cancel()
        let interval = max(device.interval, 3)
        rdPollTask = Task {
            let deadline = Date().addingTimeInterval(TimeInterval(device.expiresIn))
            while !Task.isCancelled && Date() < deadline {
                try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                if Task.isCancelled { return }
                guard let creds = try? await environment.realDebrid.pollForCredentials(deviceCode: device.deviceCode) else {
                    continue   // still pending
                }
                // Got client credentials — exchange for a token.
                if let token = try? await environment.realDebrid.obtainToken(
                    clientID: creds.clientID,
                    clientSecret: creds.clientSecret,
                    deviceCode: device.deviceCode
                ) {
                    try? KeychainStore.shared.setRealDebridToken(token)
                    await MainActor.run {
                        rdDeviceCode = nil
                        rdPollTask = nil
                    }
                    await connectUsingStoredToken()
                    return
                }
            }
            await MainActor.run { rdDeviceCode = nil }
        }
    }

    private func cancelRDDeviceFlow() {
        rdPollTask?.cancel()
        rdPollTask = nil
        rdDeviceCode = nil
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
        } catch {
            statusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            isError = true
        }
    }
}
