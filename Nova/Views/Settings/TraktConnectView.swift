//
//  TraktConnectView.swift
//  Nova
//
//  Connects a Trakt account via the device-code OAuth flow (TV-friendly): show a
//  code and a URL, the user authorizes on another device, and Nova polls until the
//  token arrives. Requires Trakt client id/secret to be set first.
//

import SwiftUI

struct TraktConnectView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @AppStorage("settings.traktLastSync") private var lastSyncStamp: Double = 0
    @State private var syncing = false
    // Confirms disconnect before the Trakt sign-out actually happens.
    @State private var confirmingDisconnect = false
    @State private var traktID = ""
    @State private var traktSecret = ""
    @State private var savedCredentialsFlash = false

    private let config = AppConfig.shared

    @State private var phase: Phase = .checking
    @State private var deviceCode: TraktDeviceCode?
    @State private var username: String?
    @State private var pollTask: Task<Void, Never>?
    @State private var errorMessage: String?

    enum Phase: Equatable {
        case checking
        case notConfigured
        case connected
        case awaitingCode
        case authorizing
        case failed
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("Trakt")
                    .font(Theme.Font.screenTitle())
                    .screenTitleStyle()
                    .foregroundStyle(Theme.Colors.textPrimary)

                switch phase {
                case .checking:
                    LoadingView(message: "Checking Trakt…").frame(height: 200)
                case .notConfigured:
                    notConfigured
                case .connected:
                    connected
                case .awaitingCode, .authorizing:
                    deviceCodeView
                case .failed:
                    failedView
                }
            }
            .padding(Theme.Spacing.edge)
            .frame(maxWidth: Theme.contentMaxWidth(1000), alignment: .leading)
        }
        .background(Theme.Colors.appBackground.ignoresSafeArea())
        .task { await onAppear() }
        .onDisappear { pollTask?.cancel() }
        .alert("Log Out of Trakt?", isPresented: $confirmingDisconnect) {
            Button("Log Out", role: .destructive) {
                env.trakt.signOut()
                username = nil
                errorMessage = nil
                phase = .notConfigured
                ToastCenter.shared.show("Logged out of Trakt", systemImage: "rectangle.portrait.and.arrow.right")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your watchlist and watched progress will stop syncing until you log in again.")
        }
    }

    private var notConfigured: some View {
        Group {
            if hasClientCredentials {
                SettingsGroup(
                    header: "Account",
                    footer: "Nova opens Trakt's secure device authorization page. Your password is never shared with Nova.",
                    rows: [
                        AnyView(SettingsNote("You are logged out. Log in to restore watchlist and progress syncing.")),
                        AnyView(
                            Button { Task { await beginDeviceFlow() } } label: {
                                SettingsRow(icon: "person.crop.circle.badge.checkmark",
                                            color: Theme.Colors.iconRed,
                                            title: "Log In to Trakt",
                                            detail: "Open secure authorization",
                                            showsChevron: false)
                            }
                            .buttonStyle(.plain)
                        )
                    ]
                )
            } else {
                SettingsGroup(
                    header: "Sign In",
                    footer: "Trakt requires app credentials before device authorization can start. After saving them, Nova opens Trakt's own authorization flow.",
                    rows: [
                        AnyView(SettingsNote("Add your Trakt client ID and secret once, then sign in with your Trakt account.")),
                        AnyView(
                            credentialRow(
                                icon: "number",
                                color: Theme.Colors.iconRed,
                                title: "Client ID",
                                text: $traktID,
                                isPresent: config.isPresent(.traktClientID)
                            )
                        ),
                        AnyView(
                            credentialRow(
                                icon: "lock.fill",
                                color: Theme.Colors.iconGraphite,
                                title: "Client Secret",
                                text: $traktSecret,
                                isPresent: config.isPresent(.traktClientSecret),
                                secure: true
                            )
                        ),
                        AnyView(saveAndSignInRow)
                    ]
                )
            }

            SettingsGroup(rows: [
                AnyView(
                    Button {
                        if let url = URL(string: "https://trakt.tv/oauth/applications") { openURL(url) }
                    } label: {
                        SettingsRow(
                            icon: "arrow.up.right.square",
                            color: Theme.Colors.iconRed,
                            title: "Create a Trakt App",
                            detail: "trakt.tv",
                            showsChevron: false
                        )
                    }
                    .buttonStyle(.plain)
                )
            ])
        }
    }

    private var hasClientCredentials: Bool {
        config.traktClientID?.isEmpty == false && config.traktClientSecret?.isEmpty == false
    }

    private func credentialRow(icon: String,
                               color: Color,
                               title: String,
                               text: Binding<String>,
                               isPresent: Bool,
                               secure: Bool = false) -> some View {
        HStack(spacing: SettingsMetrics.rowSpacing) {
            SettingsIconTile(systemImage: icon, color: color)
            VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing * 0.45) {
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
                Group {
                    if secure {
                        SecureField(isPresent ? "Stored" : "Paste value", text: text)
                    } else {
                        TextField(isPresent ? "Stored" : "Paste value", text: text)
                    }
                }
                .textFieldStyle(.plain)
                .font(.appFont(SettingsMetrics.detail))
                .foregroundStyle(Theme.Colors.textPrimary)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .textSelection(.enabled)
                #endif
            }
        }
        .padding(.horizontal, SettingsMetrics.rowSpacing + 2)
        .padding(.vertical, SettingsMetrics.rowVPad)
    }

    private var saveAndSignInRow: some View {
        Button {
            saveTraktCredentialsAndSignIn()
        } label: {
            SettingsRow(
                icon: savedCredentialsFlash ? "checkmark.circle.fill" : "person.crop.circle.badge.checkmark",
                color: savedCredentialsFlash ? .green : .red,
                title: savedCredentialsFlash ? "Saved" : "Save and Sign In",
                detail: canSaveTraktCredentials ? nil : "Add both values",
                showsChevron: false,
                tint: canSaveTraktCredentials ? nil : Theme.Colors.textTertiary
            )
        }
        .buttonStyle(.plain)
        .disabled(!canSaveTraktCredentials)
        .opacity(canSaveTraktCredentials ? 1 : 0.65)
    }

    private var canSaveTraktCredentials: Bool {
        !traktID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !traktSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveTraktCredentialsAndSignIn() {
        config.set(traktID.trimmingCharacters(in: .whitespacesAndNewlines), for: .traktClientID)
        config.set(traktSecret.trimmingCharacters(in: .whitespacesAndNewlines), for: .traktClientSecret)
        traktID = ""
        traktSecret = ""
        savedCredentialsFlash = true
        ToastCenter.shared.show("Trakt credentials saved", systemImage: "checkmark.seal.fill")
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            await MainActor.run { savedCredentialsFlash = false }
            await beginDeviceFlow()
        }
    }

    private var connected: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Label(username ?? "Connected", systemImage: "checkmark.seal.fill")
                .font(.appFont(26, weight: .semibold))
                .foregroundStyle(Theme.Colors.success)
            Text("Your watchlist and watched progress sync with Trakt.")
                .font(.appFont(20))
                .foregroundStyle(Theme.Colors.textSecondary)

            scrobbleControlPanel

            FocusableButton(title: "Log Out", systemImage: "rectangle.portrait.and.arrow.right") {
                confirmingDisconnect = true
            }
            .frame(maxWidth: Theme.isCompact ? .infinity : 320)
            .padding(.top, Theme.Spacing.sm)
        }
    }

    /// Visible scrobbling + sync controls so power users can see and adjust behavior.
    private var scrobbleControlPanel: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Scrobbling & Sync")
                .font(.appFont(20, weight: .bold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.top, Theme.Spacing.sm)

            Toggle("Scrobble playback to Trakt", isOn: $settings.traktScrobblingEnabled)
            Toggle("Sync watch progress", isOn: $settings.traktSyncProgress)
            Toggle("Sync favorites / watchlist", isOn: $settings.traktSyncFavorites)

            VStack(alignment: .leading, spacing: 4) {
                Text("Mark watched at \(settings.traktMinWatchPercent)%")
                    .font(.appFont(18))
                    .foregroundStyle(Theme.Colors.textSecondary)
                #if os(iOS)
                Slider(value: Binding(
                    get: { Double(settings.traktMinWatchPercent) },
                    set: { settings.traktMinWatchPercent = Int($0) }
                ), in: 50...100, step: 5)
                .tint(Theme.Colors.accent)
                #else
                HStack(spacing: Theme.Spacing.md) {
                    Button("−") { settings.traktMinWatchPercent = max(50, settings.traktMinWatchPercent - 5) }
                    Text("\(settings.traktMinWatchPercent)%").monospacedDigit()
                    Button("+") { settings.traktMinWatchPercent = min(100, settings.traktMinWatchPercent + 5) }
                }
                .font(.appFont(20, weight: .semibold))
                #endif
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("When local and Trakt disagree")
                    .font(.appFont(18))
                    .foregroundStyle(Theme.Colors.textSecondary)
                Picker("Conflict", selection: $settings.traktConflict) {
                    ForEach(TraktConflictBehavior.allCases) { c in
                        Text(c.rawValue).tag(c)
                    }
                }
                .pickerStyle(.segmented)
            }

            HStack(spacing: Theme.Spacing.md) {
                Text(lastSyncStamp > 0
                     ? "Last sync: \(Date(timeIntervalSince1970: lastSyncStamp).formatted(date: .abbreviated, time: .shortened))"
                     : "Not synced yet")
                    .font(.appFont(15))
                    .foregroundStyle(Theme.Colors.textTertiary)
                Spacer()
            }

            FocusableButton(title: syncing ? "Syncing…" : "Sync now", systemImage: "arrow.triangle.2.circlepath") {
                Task { await manualSync() }
            }
            .disabled(syncing)
            .frame(maxWidth: Theme.isCompact ? .infinity : 320)
        }
        .padding(Theme.Spacing.lg)
        .refinedCardBackground()
        .tint(Theme.Colors.accent)
    }

    private func manualSync() async {
        syncing = true
        await env.trakt.syncNow()
        lastSyncStamp = Date().timeIntervalSince1970
        syncing = false
        // Visible completion feedback — the sync itself finishes silently.
        ToastCenter.shared.show("Trakt sync complete", systemImage: "arrow.triangle.2.circlepath")
    }

    private var deviceCodeView: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Authorize Nova with your Trakt account.")
                .font(.appFont(22))
                .foregroundStyle(Theme.Colors.textSecondary)

            Text("Your code:")
                .font(.appFont(18))
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.top, Theme.Spacing.sm)
            Text(deviceCode?.userCode ?? "————")
                .font(.appFont(56, weight: .heavy, design: .monospaced))
                .foregroundStyle(Theme.Colors.textPrimary)
                .tracking(8)

            // Primary path: open Trakt's activation page directly so the user logs in
            // and approves in the browser, rather than typing a code on another device.
            FocusableButton(title: "Open Trakt to Sign In", systemImage: "arrow.up.right.square", prominent: true) {
                openTraktAuthorization()
            }
            .frame(maxWidth: Theme.isCompact ? .infinity : 320)
            .padding(.top, Theme.Spacing.sm)

            Text("After you approve in Trakt, come back here — it connects automatically.")
                .font(.appFont(15))
                .foregroundStyle(Theme.Colors.textTertiary)

            HStack(spacing: Theme.Spacing.sm) {
                ProgressView().tint(Theme.Colors.accent)
                Text("Waiting for authorization…")
                    .font(.appFont(18))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(.top, Theme.Spacing.md)
        }
    }

    private func openTraktAuthorization() {
        // Trakt's activation URL; appending the code pre-fills it where supported.
        let base = deviceCode?.verificationUrl ?? "https://trakt.tv/activate"
        var urlString = base
        if let code = deviceCode?.userCode {
            // trakt.tv/activate accepts the code; many flows pre-fill via this path.
            urlString = base.contains("?") ? "\(base)&code=\(code)" : "\(base)/\(code)"
        }
        guard let url = URL(string: urlString) ?? URL(string: base) else { return }
        openURL(url)
    }

    private var failedView: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(errorMessage ?? "Couldn't connect to Trakt.")
                .font(.appFont(22))
                .foregroundStyle(Theme.Colors.error)
            FocusableButton(title: "Reconnect", systemImage: "arrow.clockwise", prominent: true) {
                Task { await beginDeviceFlow() }
            }
            .frame(maxWidth: Theme.isCompact ? .infinity : 280)
            if config.value(for: .traktAccessToken)?.isEmpty == false {
                FocusableButton(title: "Log Out", systemImage: "rectangle.portrait.and.arrow.right") {
                    confirmingDisconnect = true
                }
                .frame(maxWidth: Theme.isCompact ? .infinity : 280)
            }
        }
    }

    // MARK: - Flow

    private func onAppear() async {
        phase = .checking
        // Ask the client for a *validated* status — an actual call to Trakt — instead
        // of trusting that a token string exists. This is what makes a restored but
        // expired login show as "needs reconnect" rather than a false "Connected".
        switch await env.trakt.validateConnection() {
        case .connected(let name):
            username = name
            phase = .connected
        case .disconnected:
            // Configured but no token yet — start the device flow so the user can link.
            await beginDeviceFlow()
        case .notConfigured:
            phase = .notConfigured
        case .expired:
            username = nil
            errorMessage = "Your Trakt login expired. Reconnect to restore syncing."
            phase = .failed
        case .error(let message):
            errorMessage = "Couldn't reach Trakt: \(message)"
            phase = .failed
        }
    }

    private func beginDeviceFlow() async {
        phase = .checking
        errorMessage = nil
        do {
            let code = try await env.trakt.requestDeviceCode()
            deviceCode = code
            phase = .awaitingCode
            startPolling(code)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            phase = .failed
        }
    }

    private func startPolling(_ code: TraktDeviceCode) {
        pollTask?.cancel()
        pollTask = Task {
            let interval = UInt64(max(code.interval, 1)) * 1_000_000_000
            let deadline = Date().addingTimeInterval(TimeInterval(code.expiresIn))
            while !Task.isCancelled && Date() < deadline {
                try? await Task.sleep(nanoseconds: interval)
                if Task.isCancelled { return }
                // pollForToken returns nil while the user hasn't authorized yet, or a
                // token once they have. With `try?` flattening, `polled` is a single
                // optional, so binding it means we have a real token.
                let polled = try? await env.trakt.pollForToken(deviceCode: code.deviceCode)
                if polled != nil {
                    let name = (try? await env.trakt.currentUser())?.username
                    await MainActor.run {
                        username = name
                        phase = .connected
                    }
                    return
                }
            }
            if !Task.isCancelled {
                await MainActor.run {
                    errorMessage = "The code expired. Please try again."
                    phase = .failed
                }
            }
        }
    }
}
