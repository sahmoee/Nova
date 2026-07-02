//
//  TraktConnectView.swift
//  FrameTV
//
//  Connects a Trakt account via the device-code OAuth flow (TV-friendly): show a
//  code and a URL, the user authorizes on another device, and FrameTV polls until the
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
    }

    private var notConfigured: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Add your Trakt client ID and secret in Settings ▸ Metadata & Accounts before connecting.")
                .font(.appFont(22))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text("Create a free API app at trakt.tv/oauth/applications. Use 'urn:ietf:wg:oauth:2.0:oob' as the redirect URI.")
                .font(.appFont(18))
                .foregroundStyle(Theme.Colors.textTertiary)
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

            FocusableButton(title: "Disconnect", systemImage: "rectangle.portrait.and.arrow.right") {
                Task {
                    await env.trakt.signOut()
                    phase = .notConfigured
                    await onAppear()
                }
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
    }

    private var deviceCodeView: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Authorize FrameTV with your Trakt account.")
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
            FocusableButton(title: "Try Again", systemImage: "arrow.clockwise", prominent: true) {
                Task { await beginDeviceFlow() }
            }
            .frame(maxWidth: Theme.isCompact ? .infinity : 280)
        }
    }

    // MARK: - Flow

    private func onAppear() async {
        if await env.trakt.isAuthenticated {
            username = (try? await env.trakt.currentUser())?.username
            phase = .connected
        } else if await env.trakt.isConfigured {
            await beginDeviceFlow()
        } else {
            phase = .notConfigured
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
