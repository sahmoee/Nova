//
//  AISearchSettingsView.swift
//  Nova
//
//  Lets the user point Nova at their own Cloudflare Worker for Claude-powered
//  search. Nova never stores an API key — the Worker the user deploys holds the
//  key server-side. This screen only stores the Worker's URL.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

struct AISearchSettingsView: View {
    @State private var workerURL = AISearchService.workerURLString
    @State private var workerToken = AppConfig.shared.workerToken ?? ""
    @State private var model = AISearchService.model
    @State private var showWorkerSetup = false
    @State private var didCopySetup = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("AI Search")
                    .font(Theme.Font.screenTitle())
                    .screenTitleStyle()
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("Search for movies and shows using natural language, powered by Claude. Nova uses its secure unified service by default; advanced users can still enter a self-hosted Worker URL.")
                    .font(.appFont(19))
                    .foregroundStyle(Theme.Colors.textSecondary)

                Text("Worker URL")
                    .font(.appFont(17, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                HStack(spacing: Theme.Spacing.sm) {
                    TextField(NovaWorkerConfiguration.exampleBaseURL, text: $workerURL)
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
                        .onChange(of: workerURL) { _, newValue in
                            AISearchService.workerURLString = newValue
                        }
                    #if os(iOS)
                    PasteButton(text: $workerURL) { pasted in
                        AISearchService.workerURLString = pasted
                    }
                    #endif
                }

                Text("Worker Token (optional)")
                    .font(.appFont(17, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.top, Theme.Spacing.sm)
                SecureField("Bearer token (if your Worker sets NOVA_SHARED_TOKEN)", text: $workerToken)
                    .textFieldStyle(.plain)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    #endif
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .onChange(of: workerToken) { _, newValue in
                        AppConfig.shared.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), for: .workerToken)
                    }
                Text("Stored securely in your Keychain and sent as a Bearer token to your Worker. Leave blank if your Worker doesn't require one.")
                    .font(.appFont(14))
                    .foregroundStyle(Theme.Colors.textTertiary)

                Text("Model")
                    .font(.appFont(17, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                TextField("Worker default", text: $model)
                    .textFieldStyle(.plain)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    #endif
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .onChange(of: model) { _, value in AISearchService.model = value }
                Text("Leave blank to retain Nova's current automatic model. Your private Worker may honor this model ID or enforce its own allowlist.")
                    .font(.appFont(14))
                    .foregroundStyle(Theme.Colors.textTertiary)

                Label(AISearchService.isConfigured ? "AI search is ready" : "Not configured yet",
                      systemImage: AISearchService.isConfigured ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .font(.appFont(17))
                    .foregroundStyle(AISearchService.isConfigured ? Theme.Colors.success : Theme.Colors.textTertiary)

                Button {
                    showWorkerSetup.toggle()
                } label: {
                    Label(showWorkerSetup ? "Hide self-hosting setup" : "Advanced: self-host the Worker",
                          systemImage: "chevron.right.circle")
                        .font(.appFont(18, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                }
                .novaRowStyle()

                if showWorkerSetup { workerInstructions }
            }
            .padding(.horizontal, Theme.Spacing.edge)
            .padding(.bottom, Theme.Spacing.xl)
            .frame(maxWidth: Theme.contentMaxWidth(1000), alignment: .leading)
        }
        .background(Theme.Colors.appBackground.ignoresSafeArea())
        .dismissKeyboardOnTap()
    }

    private var workerInstructions: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            instruction(1, "Clone the UnifiedWorker repository and run npm ci.")
            instruction(2, "Set ANTHROPIC_API_KEY with Wrangler. Optionally set NOVA_SHARED_TOKEN and enter the same token above.")
            instruction(3, "Run npm run check, then deploy your own Worker and paste its /nova endpoint above.")

            HStack {
                Text("Worker setup commands")
                    .font(.appFont(16, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                #if os(iOS)
                Button {
                    UIPasteboard.general.string = workerSetupCommands
                    didCopySetup = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { didCopySetup = false }
                } label: {
                    Label(didCopySetup ? "Copied" : "Copy",
                          systemImage: didCopySetup ? "checkmark" : "doc.on.doc")
                        .font(.appFont(15, weight: .semibold))
                        .foregroundStyle(didCopySetup ? Theme.Colors.success : Theme.Colors.accent)
                }
                .buttonStyle(.plain)
                #endif
            }
            ScrollView(.horizontal, showsIndicators: true) {
                Text(workerSetupCommands)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    #if os(iOS)
                    .textSelection(.enabled)
                    #endif
                    .padding(Theme.Spacing.md)
            }
            .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

            Text("Your provider key lives only in your Worker's secrets and is never sent to or stored by Nova. This keeps Nova's existing setup while letting every installation use a separate provider account and model.")
                .font(.appFont(14))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
    }

    private func instruction(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Text("\(n)")
                .font(.appFont(15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Theme.Colors.accent, in: Circle())
            Text(text)
                .font(.appFont(17))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private var workerSetupCommands: String {
        """
        git clone https://github.com/sahmoee/UnifiedWorker.git
        cd UnifiedWorker
        npm ci
        npx wrangler secret put ANTHROPIC_API_KEY
        # Optional but recommended for private access:
        npx wrangler secret put NOVA_SHARED_TOKEN
        npm run check
        npm run deploy
        """
    }
}
