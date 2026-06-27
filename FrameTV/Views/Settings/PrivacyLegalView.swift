//
//  PrivacyLegalView.swift
//  FrameTV
//
//  Plain-language privacy and legal explanation screen.
//

import SwiftUI

struct PrivacyLegalView: View {
    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text("Privacy & Legal")
                        .font(Theme.Font.screenTitle())
                        .screenTitleStyle()
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .padding(.top, Theme.Spacing.lg)

                    block(
                        title: "What FrameTV is",
                        body: "FrameTV is a personal media player for content you own, control, or are authorized to access. It does not include a content catalog, search engine, scraper, or any index of media sources."
                    )

                    block(
                        title: "Your data stays on your device",
                        body: "Your library, watch history, and settings are stored locally. FrameTV has no analytics and no servers of its own. The only network calls FrameTV makes are directly to services you configure yourself."
                    )

                    block(
                        title: "Credentials",
                        body: "Your Real-Debrid token and SMB passwords are stored securely in the system Keychain. They are never written to logs and never leave your device except to authenticate with the service you entered them for."
                    )

                    block(
                        title: "Your responsibility",
                        body: "You are responsible for ensuring you have the legal right to access anything you add. Magnet and link flows require you to confirm you own or are authorized to access the content."
                    )

                    block(
                        title: "No piracy features",
                        body: "FrameTV does not bypass DRM, does not suggest sources, and does not help locate copyrighted material. It is a player, not a finder."
                    )
                }
                .padding(.horizontal, Theme.Spacing.edge)
                .padding(.bottom, Theme.Spacing.xl)
                .frame(maxWidth: Theme.contentMaxWidth(1100), alignment: .leading)
            }
        }
    }

    private func block(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(.appFont(28, weight: .bold))
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(body)
                .font(.appFont(21))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}
