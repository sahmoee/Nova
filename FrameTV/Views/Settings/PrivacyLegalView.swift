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
                        body: "Your library, watch history, and settings are stored locally. FrameTV has no analytics and no servers of its own. The network calls FrameTV makes are to services you configure yourself, such as your metadata provider, your Real-Debrid account, your SMB shares, and (if you set it up) your own AI Worker."
                    )

                    block(
                        title: "AI features",
                        body: "AI search and AI shelf and playlist building are optional and off until you add your own AI Worker URL. When you use them, the text you type and, for library search, the titles in your library are sent to the Worker you deployed, which forwards them to the Anthropic API to generate suggestions. FrameTV does not run this service; you do. If you never configure a Worker, no data is sent for AI, and AI library search falls back to a local match on your device. You can stop all AI data sharing at any time by removing the Worker URL in Settings."
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

                    // Open-source acknowledgements. Listing licenses (especially VLCKit's
                    // LGPL) in-app keeps FrameTV compliant with their terms.
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Open-Source Acknowledgements")
                            .font(.appFont(28, weight: .bold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("FrameTV is built with the following open-source components. Thank you to their authors.")
                            .font(.appFont(20))
                            .foregroundStyle(Theme.Colors.textSecondary)

                        acknowledgement(
                            name: "VLCKit",
                            license: "LGPL v2.1 or later",
                            detail: "Provides the VLC-based player engine for broad format support. © VideoLAN and the VLCKit authors. VLCKit is used as a dynamically linked library under the LGPL; its source is available at code.videolan.org.")
                        acknowledgement(
                            name: "vlckit-spm",
                            license: "Packaging under VLCKit's terms",
                            detail: "Swift Package Manager distribution of VLCKit. github.com/tylerjonesio/vlckit-spm.")
                        acknowledgement(
                            name: "AMSMB2",
                            license: "MIT License",
                            detail: "Provides SMB network share access. © Amir Abbas Mousavian. github.com/amosavian/AMSMB2.")

                        Text("Metadata, when enabled, is provided by The Movie Database (TMDB) using your own API key. This product uses the TMDB API but is not endorsed or certified by TMDB.")
                            .font(.appFont(16))
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .padding(.top, Theme.Spacing.xs)
                    }
                    .padding(Theme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
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

    private func acknowledgement(name: String, license: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(name)
                    .font(.appFont(20, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(license)
                    .font(.appFont(14, weight: .medium))
                    .foregroundStyle(Theme.Colors.accent)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Theme.Colors.accent.opacity(0.14), in: Capsule())
            }
            Text(detail)
                .font(.appFont(16))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(.top, Theme.Spacing.xs)
    }
}
