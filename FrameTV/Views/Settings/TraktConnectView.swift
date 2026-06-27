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
    @Environment(\.dismiss) private var dismiss

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
        .background(Theme.Colors.background.ignoresSafeArea())
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

    private var deviceCodeView: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Go to this address on your phone or computer:")
                .font(.appFont(22))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(deviceCode?.verificationUrl ?? "trakt.tv/activate")
                .font(.appFont(34, weight: .bold))
                .foregroundStyle(Theme.Colors.accent)

            Text("Enter this code:")
                .font(.appFont(22))
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.top, Theme.Spacing.sm)
            Text(deviceCode?.userCode ?? "————")
                .font(.appFont(64, weight: .heavy, design: .monospaced))
                .foregroundStyle(Theme.Colors.textPrimary)
                .tracking(8)

            HStack(spacing: Theme.Spacing.sm) {
                ProgressView().tint(Theme.Colors.accent)
                Text("Waiting for authorization…")
                    .font(.appFont(18))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(.top, Theme.Spacing.md)
        }
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
                if let token = try? await env.trakt.pollForToken(deviceCode: code.deviceCode), token != nil {
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
