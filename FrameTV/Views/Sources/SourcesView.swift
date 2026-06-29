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
    /// Drives the SMB card's real status (configured vs not) from saved shares.
    @StateObject private var smbModel = SMBSharesModel()

    // Flexible columns so cards stretch to fill the row: fewer, wider cards on
    // iPhone; more on iPad/tvOS. This avoids the narrow-cells-with-gaps look.
    private var columns: [GridItem] {
        let count = Theme.isCompact ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.lg), count: count)
    }

    var body: some View {
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

                    healthSummary
                        .padding(.horizontal, Theme.Spacing.edge)

                    LazyVGrid(columns: columns, spacing: Theme.Spacing.lg) {
                        NavigationLink { RealDebridView() } label: {
                            SourceCard(title: "Real-Debrid",
                                       systemImage: SourceType.realDebrid.systemImage,
                                       status: SourceHealth.realDebrid().status) {}
                                .allowsHitTesting(false)
                        }.buttonStyle(.plain)

                        NavigationLink { AddonsView() } label: {
                            SourceCard(title: "Addons",
                                       systemImage: SourceType.addon.systemImage,
                                       status: SourceHealth.addons(env.addonStore).status) {}
                                .allowsHitTesting(false)
                        }.buttonStyle(.plain)

                        NavigationLink { SMBListView() } label: {
                            SourceCard(title: "SMB Shares",
                                       systemImage: SourceType.smb.systemImage,
                                       status: SourceHealth.smb(shareCount: smbModel.shares.count).status) {}
                                .allowsHitTesting(false)
                        }.buttonStyle(.plain)

                        NavigationLink { TraktConnectView() } label: {
                            SourceCard(title: "Trakt",
                                       systemImage: SourceType.trakt.systemImage,
                                       status: SourceHealth.trakt().status) {}
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
                                       status: SourceHealth.realDebrid().status) {}
                                .allowsHitTesting(false)
                        }.buttonStyle(.plain)
                    }
                    .padding(.horizontal, Theme.Spacing.edge)
                    .padding(.bottom, Theme.Spacing.xl)
                }
            }
        }
        .navigationTitle("Sources")
    }

    /// A compact banner summarizing the metadata-affecting sources (TMDB / Trakt /
    /// Real-Debrid / Addons), so missing keys are obvious at a glance.
    private var healthSummary: some View {
        let items = [SourceHealth.realDebrid(), SourceHealth.tmdb(),
                     SourceHealth.trakt(), SourceHealth.addons(env.addonStore)]
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ForEach(items) { item in
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: item.systemImage)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: 26)
                    Text(item.name)
                        .font(.appFont(18, weight: .medium))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    if let detail = item.detail {
                        Text(detail)
                            .font(.appFont(15))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    HStack(spacing: 6) {
                        Circle().fill(item.status.color).frame(width: 8, height: 8)
                        Text(statusText(item.status))
                            .font(.appFont(15, weight: .semibold))
                            .foregroundStyle(item.status.color)
                    }
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func statusText(_ status: SourceStatus) -> String {
        if case .error(let m) = status { return m }
        return status.label
    }
}
