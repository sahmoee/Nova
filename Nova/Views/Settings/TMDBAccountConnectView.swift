//
//  TMDBAccountConnectView.swift
//  Nova
//
//  Connects the user's TMDB account as an optional tracker (watchlist read/write).
//  Uses TMDB's v3 session flow: create a request token, the user approves it in the
//  browser, then Nova exchanges it for a session. Reuses the existing TMDB API key.
//  TMDB has no "watched" state, so this contributes the watchlist only.
//

import SwiftUI

struct TMDBAccountConnectView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.openURL) private var openURL

    private let config = AppConfig.shared

    @State private var phase: Phase = .checking
    @State private var requestToken: String?
    @State private var username: String?
    @State private var errorMessage: String?
    @State private var confirmingDisconnect = false

    enum Phase: Equatable {
        case checking, noKey, needsAuth, awaitingApproval, connected, failed
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("TMDB Account")
                    .font(Theme.Font.screenTitle())
                    .screenTitleStyle()
                    .foregroundStyle(Theme.Colors.textPrimary)

                switch phase {
                case .checking:         LoadingView(message: "Checking TMDB…").frame(height: 160)
                case .noKey:            noKey
                case .needsAuth:        needsAuth
                case .awaitingApproval: awaitingApproval
                case .connected:        connected
                case .failed:           failedView
                }

                Text("Adds your TMDB watchlist as a tracker. TMDB has no watched state, so playback isn't reported to it.")
                    .font(.appFont(13))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.top, Theme.Spacing.sm)
            }
            .padding(Theme.Spacing.edge)
            .frame(maxWidth: Theme.contentMaxWidth(1000), alignment: .leading)
        }
        .background(Theme.Colors.appBackground.ignoresSafeArea())
        .task { await onAppear() }
        .alert("Disconnect TMDB Account?", isPresented: $confirmingDisconnect) {
            Button("Disconnect", role: .destructive) {
                Task {
                    await env.tmdbTracker.signOut()
                    username = nil
                    phase = .needsAuth
                    ToastCenter.shared.show("Disconnected TMDB account", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your TMDB watchlist will stop syncing until you reconnect.")
        }
    }

    private var noKey: some View {
        Text("Add your TMDB API key first (Settings ▸ Accounts), then connect your account here.")
            .font(.appFont(18))
            .foregroundStyle(Theme.Colors.textSecondary)
    }

    private var needsAuth: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Connect your TMDB account to sync your watchlist.")
                .font(.appFont(18))
                .foregroundStyle(Theme.Colors.textSecondary)
            FocusableButton(title: "Connect TMDB Account", systemImage: "person.crop.circle.badge.checkmark", prominent: true) {
                Task { await beginAuth() }
            }
            .frame(maxWidth: Theme.isCompact ? .infinity : 320)
        }
    }

    private var awaitingApproval: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Approve Nova in your browser, then come back and tap Finish.")
                .font(.appFont(20))
                .foregroundStyle(Theme.Colors.textSecondary)
            FocusableButton(title: "Open TMDB to Approve", systemImage: "arrow.up.right.square", prominent: true) {
                if let token = requestToken, let url = TMDBAccountClient.approvalURL(requestToken: token) {
                    openURL(url)
                }
            }
            .frame(maxWidth: Theme.isCompact ? .infinity : 320)
            FocusableButton(title: "Finish Connecting", systemImage: "checkmark.circle") {
                Task { await finishAuth() }
            }
            .frame(maxWidth: Theme.isCompact ? .infinity : 320)
        }
    }

    private var connected: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Label(username ?? "Connected", systemImage: "checkmark.seal.fill")
                .font(.appFont(26, weight: .semibold))
                .foregroundStyle(Theme.Colors.success)
            Text("Your TMDB watchlist is now available as a tracker.")
                .font(.appFont(20))
                .foregroundStyle(Theme.Colors.textSecondary)
            FocusableButton(title: "Disconnect", systemImage: "rectangle.portrait.and.arrow.right") {
                confirmingDisconnect = true
            }
            .frame(maxWidth: Theme.isCompact ? .infinity : 320)
            .padding(.top, Theme.Spacing.sm)
        }
    }

    private var failedView: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(errorMessage ?? "Couldn't connect your TMDB account.")
                .font(.appFont(22))
                .foregroundStyle(Theme.Colors.error)
            FocusableButton(title: "Try Again", systemImage: "arrow.clockwise", prominent: true) {
                Task { await beginAuth() }
            }
            .frame(maxWidth: Theme.isCompact ? .infinity : 280)
        }
    }

    // MARK: - Flow

    private func onAppear() async {
        phase = .checking
        switch await env.tmdbTracker.validateConnection() {
        case .connected(let name): username = name; phase = .connected
        case .disconnected:        phase = .needsAuth
        case .notConfigured:       phase = .noKey
        case .expired:             phase = .needsAuth
        case .error(let message):
            errorMessage = "Couldn't reach TMDB: \(message)"
            phase = .failed
        }
    }

    private func beginAuth() async {
        phase = .checking
        errorMessage = nil
        do {
            let token = try await env.tmdbTracker.createRequestToken()
            requestToken = token.requestToken
            phase = .awaitingApproval
            if let url = TMDBAccountClient.approvalURL(requestToken: token.requestToken) { openURL(url) }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            phase = .failed
        }
    }

    private func finishAuth() async {
        guard let token = requestToken else { phase = .needsAuth; return }
        phase = .checking
        let ok = (try? await env.tmdbTracker.createSession(requestToken: token)) ?? false
        if ok {
            if case .connected(let name) = await env.tmdbTracker.validateConnection() { username = name }
            phase = .connected
            ToastCenter.shared.show("TMDB account connected", systemImage: "checkmark.seal.fill")
        } else {
            errorMessage = "Approval not detected yet. Approve in the browser, then tap Finish again."
            phase = .awaitingApproval
        }
    }
}
