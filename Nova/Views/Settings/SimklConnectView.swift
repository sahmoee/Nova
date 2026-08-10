//
//  SimklConnectView.swift
//  Nova
//
//  Connects a SIMKL account via SIMKL's PIN flow: show a short code + the
//  verification URL (simkl.com/pin), the user approves on another device, and Nova
//  polls until the token arrives. Only a SIMKL client id is required (no secret).
//

import SwiftUI

struct SimklConnectView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.openURL) private var openURL

    private let config = AppConfig.shared

    @State private var phase: Phase = .checking
    @State private var clientIDField = ""
    @State private var pin: SimklPin?
    @State private var username: String?
    @State private var errorMessage: String?
    @State private var pollTask: Task<Void, Never>?
    @State private var confirmingDisconnect = false

    enum Phase: Equatable {
        case checking, notConfigured, awaitingCode, connected, failed
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("SIMKL")
                    .font(Theme.Font.screenTitle())
                    .screenTitleStyle()
                    .foregroundStyle(Theme.Colors.textPrimary)

                switch phase {
                case .checking:      LoadingView(message: "Checking SIMKL…").frame(height: 160)
                case .notConfigured: notConfigured
                case .awaitingCode:  deviceCodeView
                case .connected:     connected
                case .failed:        failedView
                }

                Button {
                    if let url = URL(string: "https://simkl.com/settings/developer/") { openURL(url) }
                } label: {
                    Label("Create a SIMKL App", systemImage: "arrow.up.right.square")
                        .font(.appFont(16, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                }
                .buttonStyle(.plain)
                .padding(.top, Theme.Spacing.sm)

                Text("Trending and watchlist data powered by SIMKL.")
                    .font(.appFont(13))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(Theme.Spacing.edge)
            .frame(maxWidth: Theme.contentMaxWidth(1000), alignment: .leading)
        }
        .background(Theme.Colors.appBackground.ignoresSafeArea())
        .task { await onAppear() }
        .onDisappear { pollTask?.cancel() }
        .alert("Log Out of SIMKL?", isPresented: $confirmingDisconnect) {
            Button("Log Out", role: .destructive) {
                Task {
                    await env.simkl.signOut()
                    username = nil
                    phase = .notConfigured
                    ToastCenter.shared.show("Logged out of SIMKL", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your SIMKL watchlist and watched sync will stop until you log in again.")
        }
    }

    private var notConfigured: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Enter your SIMKL client ID, then sign in. Create an app at simkl.com to get one — no secret needed.")
                .font(.appFont(18))
                .foregroundStyle(Theme.Colors.textSecondary)

            TextField("SIMKL client ID", text: $clientIDField)
                .textFieldStyle(.plain)
                .font(.appFont(16, weight: .regular, design: .monospaced))
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(12)
                .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: 10))
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                #endif

            FocusableButton(title: "Save and Sign In", systemImage: "person.crop.circle.badge.checkmark", prominent: true) {
                let id = clientIDField.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !id.isEmpty else { return }
                config.set(id, for: .simklClientID)
                clientIDField = ""
                ToastCenter.shared.show("SIMKL client ID saved", systemImage: "checkmark.seal.fill")
                Task { await beginPinFlow() }
            }
            .frame(maxWidth: Theme.isCompact ? .infinity : 320)
        }
    }

    private var deviceCodeView: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Authorize Nova with your SIMKL account.")
                .font(.appFont(22))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text("Your code:")
                .font(.appFont(18))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(pin?.userCode ?? "————")
                .font(.appFont(56, weight: .heavy, design: .monospaced))
                .foregroundStyle(Theme.Colors.textPrimary)
                .tracking(8)

            FocusableButton(title: "Open SIMKL to Sign In", systemImage: "arrow.up.right.square", prominent: true) {
                let base = pin?.verificationUrl ?? "https://simkl.com/pin/"
                if let url = URL(string: base) { openURL(url) }
            }
            .frame(maxWidth: Theme.isCompact ? .infinity : 320)

            Text("After you approve in SIMKL, come back here — it connects automatically.")
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

    private var connected: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Label(username ?? "Connected", systemImage: "checkmark.seal.fill")
                .font(.appFont(26, weight: .semibold))
                .foregroundStyle(Theme.Colors.success)
            Text("Your watchlist and watched progress sync with SIMKL.")
                .font(.appFont(20))
                .foregroundStyle(Theme.Colors.textSecondary)
            FocusableButton(title: "Log Out", systemImage: "rectangle.portrait.and.arrow.right") {
                confirmingDisconnect = true
            }
            .frame(maxWidth: Theme.isCompact ? .infinity : 320)
            .padding(.top, Theme.Spacing.sm)
        }
    }

    private var failedView: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(errorMessage ?? "Couldn't connect to SIMKL.")
                .font(.appFont(22))
                .foregroundStyle(Theme.Colors.error)
            FocusableButton(title: "Try Again", systemImage: "arrow.clockwise", prominent: true) {
                Task { await beginPinFlow() }
            }
            .frame(maxWidth: Theme.isCompact ? .infinity : 280)
        }
    }

    // MARK: - Flow

    private func onAppear() async {
        phase = .checking
        switch await env.simkl.validateConnection() {
        case .connected(let name): username = name; phase = .connected
        case .disconnected:        await beginPinFlow()
        case .notConfigured:       phase = .notConfigured
        case .expired:
            errorMessage = "Your SIMKL login expired. Reconnect to restore syncing."
            phase = .failed
        case .error(let message):
            errorMessage = "Couldn't reach SIMKL: \(message)"
            phase = .failed
        }
    }

    private func beginPinFlow() async {
        phase = .checking
        errorMessage = nil
        do {
            let code = try await env.simkl.requestPin()
            pin = code
            phase = .awaitingCode
            startPolling(code)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            phase = .failed
        }
    }

    private func startPolling(_ code: SimklPin) {
        pollTask?.cancel()
        pollTask = Task {
            let interval = UInt64(max(code.interval, 1)) * 1_000_000_000
            let deadline = Date().addingTimeInterval(TimeInterval(code.expiresIn))
            while !Task.isCancelled && Date() < deadline {
                try? await Task.sleep(nanoseconds: interval)
                if Task.isCancelled { return }
                let token = try? await env.simkl.pollForToken(userCode: code.userCode)
                if token != nil {
                    let name: String?
                    if case .connected(let n) = await env.simkl.validateConnection() { name = n } else { name = nil }
                    await MainActor.run { username = name; phase = .connected }
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
