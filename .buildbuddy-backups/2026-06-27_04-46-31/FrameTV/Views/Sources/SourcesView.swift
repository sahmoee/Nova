//
//  SourcesView.swift
//  FrameTV
//
//  Grid of source cards. Each routes to its management screen. Status shown
//  is best-effort for Phase 1/2 (SMB/Real-Debrid become live in later phases).
//

import SwiftUI

struct SourcesView: View {
    @Binding var path: NavigationPath
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var library: LibraryStore

    private let columns = [GridItem(.adaptive(minimum: Theme.CardSize.sourceWidth),
                                    spacing: Theme.Spacing.md)]

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        Text("Sources")
                            .font(Theme.Font.screenTitle())
                            .screenTitleStyle()
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .padding(.horizontal, Theme.Spacing.edge)
                            .padding(.top, Theme.Spacing.lg)

                        LazyVGrid(columns: columns, spacing: Theme.Spacing.lg) {
                            NavigationLink { SMBListView() } label: {
                                SourceCard(title: "SMB Shares",
                                           systemImage: SourceType.smb.systemImage,
                                           status: .notConfigured) {}
                                    .allowsHitTesting(false)
                            }.buttonStyle(.plain)

                            NavigationLink { RealDebridView() } label: {
                                SourceCard(title: "Real-Debrid",
                                           systemImage: SourceType.realDebrid.systemImage,
                                           status: realDebridStatus) {}
                                    .allowsHitTesting(false)
                            }.buttonStyle(.plain)

                            NavigationLink { DirectURLView() } label: {
                                SourceCard(title: "Direct URL",
                                           systemImage: SourceType.directURL.systemImage,
                                           status: .connected,
                                           lastSynced: Date()) {}
                                    .allowsHitTesting(false)
                            }.buttonStyle(.plain)

                            NavigationLink { MagnetView() } label: {
                                SourceCard(title: "Magnet Link",
                                           systemImage: "scope",
                                           status: realDebridStatus) {}
                                    .allowsHitTesting(false)
                            }.buttonStyle(.plain)

                            NavigationLink { AddonsView() } label: {
                                SourceCard(title: "Addons",
                                           systemImage: SourceType.addon.systemImage,
                                           status: addonStatus) {}
                                    .allowsHitTesting(false)
                            }.buttonStyle(.plain)

                            NavigationLink { TraktConnectView() } label: {
                                SourceCard(title: "Trakt",
                                           systemImage: SourceType.trakt.systemImage,
                                           status: .notConfigured) {}
                                    .allowsHitTesting(false)
                            }.buttonStyle(.plain)

                            SourceCard(title: "Public Domain Feeds",
                                       systemImage: SourceType.publicDomain.systemImage,
                                       status: .notConfigured) {}
                        }
                        .padding(.horizontal, Theme.Spacing.edge)
                        .padding(.bottom, Theme.Spacing.xl)
                    }
                }
            }
        }
    }

    private var realDebridStatus: SourceStatus {
        KeychainStore.shared.realDebridToken == nil ? .notConfigured : .connected
    }

    private var addonStatus: SourceStatus {
        env.addonStore.streamAddons.isEmpty ? .notConfigured : .connected
    }
}
