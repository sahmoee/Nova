//
//  PrivacyLegalView.swift
//  FrameTV
//
//  Plain-language privacy and legal explanation screen.
//

import SwiftUI

struct PrivacyLegalView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text("Privacy & Legal")
                        .font(Theme.Font.screenTitle())
                        .screenTitleStyle()
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .padding(.top, Theme.Spacing.lg)

                    // Review-safe configuration: hides the stream-resolution
                    // surfaces (Real-Debrid, magnet, addons) on this device only.
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Toggle(isOn: $settings.reviewSafeMode) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Review-Safe Mode")
                                    .font(.appFont(20, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Text("Hides Real-Debrid, magnet, and addon features on this device. Direct URLs, SMB, Trakt, and your library are unaffected. Not synced to iCloud.")
                                    .font(.appFont(15))
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                        }
                        .tint(Theme.Colors.accent)
                    }
                    .padding(Theme.Spacing.md)
                    .refinedCardBackground()

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

                    // Source permissions audit: exactly what each configured source
                    // can access. Pure transparency; nothing here changes behavior.
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("What Each Source Can Do")
                            .font(.appFont(28, weight: .bold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("FrameTV only talks to the services you set up. Here is exactly what each one is used for.")
                            .font(.appFont(18))
                            .foregroundStyle(Theme.Colors.textSecondary)

                        permission(icon: "photo.on.rectangle", source: "TMDB",
                                   detail: "Posters, backdrops, episode metadata. Uses your API key.")
                        permission(icon: "checklist", source: "Trakt",
                                   detail: "Watchlist, lists, trending, and watch progress you choose to sync.")
                        permission(icon: "star.circle", source: "OMDb",
                                   detail: "IMDb, Rotten Tomatoes, and Metacritic ratings. Uses your API key.")
                        permission(icon: "arrow.down.circle", source: "Real-Debrid",
                                   detail: "Resolves links through your own account. FrameTV never sees your password, only the token you authorize.")
                        permission(icon: "externaldrive.connected.to.line.below", source: "SMB",
                                   detail: "Reads the specific network shares you add, on your local network only.")
                        permission(icon: "sparkles", source: "AI Worker",
                                   detail: "Receives only the search text you type (and, for library search, your library titles). Off until you add a Worker URL.")
                    }
                    .padding(Theme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .refinedCardBackground()

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
                    .refinedCardBackground()
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
        .refinedCardBackground()
    }

    private func permission(icon: String, source: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.appFont(22, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(source)
                    .font(.appFont(19, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(detail)
                    .font(.appFont(16))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
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
