//
//  SourcesView.swift
//  Nova
//
//  Grid of source cards. Each routes to its management screen. Status shown
//  is best-effort for Phase 1/2 (SMB/Real-Debrid become live in later phases).
//

import SwiftUI

struct SourcesView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var library: LibraryStore
    /// Drives the SMB card's real status (configured vs not) from saved shares.
    @StateObject private var smbModel = SMBSharesModel()
    @StateObject private var healthMonitor = SourceHealthMonitor()
    @State private var rdUser: RealDebridUser?

    // Flexible columns so cards stretch to fill the row: fewer, wider cards on
    // iPhone; more on iPad/tvOS. This avoids the narrow-cells-with-gaps look.
    private var columns: [GridItem] {
        let count = Theme.isCompact ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.lg), count: count)
    }

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()

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
                        if !settings.reviewSafeMode {
                            NavigationLink { RealDebridView() } label: {
                                SourceCard(title: "Real-Debrid",
                                           systemImage: SourceType.realDebrid.systemImage,
                                           status: liveStatus("realdebrid", fallback: SourceHealth.realDebrid().status),
                                           lastSynced: lastChecked("realdebrid"), isInteractive: false) {}
                            }.buttonStyle(.plain)
                        }

                        if !settings.reviewSafeMode {
                            NavigationLink { AddonsView() } label: {
                                SourceCard(title: "Addons",
                                           systemImage: SourceType.addon.systemImage,
                                           status: liveStatus("addons", fallback: SourceHealth.addons(env.addonStore).status),
                                           lastSynced: lastChecked("addons"), isInteractive: false) {}
                            }.buttonStyle(.plain)
                        }

                        NavigationLink { SMBListView() } label: {
                            SourceCard(title: "SMB Shares",
                                       systemImage: SourceType.smb.systemImage,
                                       status: liveStatus("smb", fallback: SourceHealth.smb(shareCount: smbModel.shares.count).status),
                                       lastSynced: lastChecked("smb"), isInteractive: false) {}
                        }.buttonStyle(.plain)

                        NavigationLink { TraktConnectView() } label: {
                            SourceCard(title: "Trakt",
                                       systemImage: SourceType.trakt.systemImage,
                                       status: liveStatus("trakt", fallback: SourceHealth.trakt().status),
                                       lastSynced: lastChecked("trakt"), isInteractive: false) {}
                        }.buttonStyle(.plain)

                        NavigationLink { SimklConnectView() } label: {
                            SourceCard(title: "SIMKL",
                                       systemImage: "checkmark.seal",
                                       status: trackerStatus(clientID: AppConfig.shared.simklClientID,
                                                             token: .simklAccessToken), isInteractive: false) {}
                        }.buttonStyle(.plain)

                        NavigationLink { TMDBAccountConnectView() } label: {
                            SourceCard(title: "TMDB Account",
                                       systemImage: "person.crop.circle",
                                       status: trackerStatus(clientID: AppConfig.shared.tmdbKey,
                                                             token: .tmdbSessionID), isInteractive: false) {}
                        }.buttonStyle(.plain)

                        NavigationLink { DirectURLView() } label: {
                            SourceCard(title: "Direct URL",
                                       systemImage: SourceType.directURL.systemImage,
                                       status: .connected,
                                       lastSynced: Date(), isInteractive: false) {}
                        }.buttonStyle(.plain)

                        if !settings.reviewSafeMode {
                        NavigationLink { MagnetView() } label: {
                            SourceCard(title: "Magnet Link",
                                       systemImage: "scope",
                                       status: SourceHealth.realDebrid().status, isInteractive: false) {}
                        }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.edge)
                    .padding(.bottom, Theme.Spacing.xl)
                }
            }
        }
        .navigationTitle("Sources")
        .task {
            // Live Real-Debrid account detail (premium days left) when connected.
            if KeychainStore.shared.realDebridToken != nil {
                rdUser = try? await env.realDebrid.validateToken()
            }
            await healthMonitor.refresh(environment: env, smbShares: smbModel.shares)
        }
    }

    /// A compact banner summarizing the metadata-affecting sources (TMDB / Trakt /
    /// Real-Debrid / Addons), so missing keys are obvious at a glance.
    private var healthSummary: some View {
        let items = healthMonitor.items.isEmpty
            ? [SourceHealth.realDebrid(), SourceHealth.tmdb(),
               SourceHealth.trakt(), SourceHealth.addons(env.addonStore)]
            : healthMonitor.items
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("Live health")
                    .font(.appFont(17, weight: .bold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Button(healthMonitor.isChecking ? "Checking…" : "Refresh") {
                    Task { await healthMonitor.refresh(environment: env, smbShares: smbModel.shares) }
                }
                .disabled(healthMonitor.isChecking)
                .font(.appFont(15, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent)
            }
            ForEach(items) { item in
                // Each row is a "Fix" deep link straight into the screen that
                // resolves it, instead of a read-only status line.
                NavigationLink {
                    fixDestination(for: item.name)
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: item.systemImage)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .frame(width: 26)
                        Text(item.name)
                            .font(.appFont(18, weight: .medium))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Spacer()
                        if let detail = displayDetail(for: item) {
                            Text(detail)
                                .font(.appFont(15))
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                        if let checked = item.lastChecked {
                            Text(checked, style: .relative)
                                .font(.appFont(13))
                                .foregroundStyle(Date().timeIntervalSince(checked) > 15 * 60
                                                 ? Theme.Colors.warning : Theme.Colors.textTertiary)
                        }
                        HStack(spacing: 6) {
                            Circle().fill(item.status.color).frame(width: 8, height: 8)
                            Text(statusText(item.status))
                                .font(.appFont(15, weight: .semibold))
                                .foregroundStyle(item.status.color)
                        }
                        Image(systemName: "chevron.right")
                            .font(.appFont(13, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.Spacing.md)
        .refinedCardBackground()
    }

    /// Synchronous status for the optional trackers, from stored credentials:
    /// connected if a token exists, not-connected if only the client key is set,
    /// otherwise not-set-up.
    private func trackerStatus(clientID: String?, token: CredentialKey) -> SourceStatus {
        if AppConfig.shared.value(for: token)?.isEmpty == false { return .connected }
        if clientID?.isEmpty == false { return .disconnected }
        return .notConfigured
    }

    private func liveStatus(_ id: String, fallback: SourceStatus) -> SourceStatus {
        healthMonitor.items.first(where: { $0.id == id })?.status ?? fallback
    }

    private func lastChecked(_ id: String) -> Date? {
        healthMonitor.items.first(where: { $0.id == id })?.lastChecked
    }

    /// Live account detail overrides: Real-Debrid shows premium days remaining.
    private func displayDetail(for item: SourceHealthItem) -> String? {
        if item.name == "Real-Debrid", let user = rdUser {
            if user.isPremium, let seconds = user.premium, seconds > 0 {
                let days = seconds / 86_400
                return days > 0 ? "Premium · \(days) day\(days == 1 ? "" : "s") left" : "Premium"
            }
            return "Free account"
        }
        return item.detail
    }

    /// The management screen that fixes (or configures) each health row.
    @ViewBuilder
    private func fixDestination(for name: String) -> some View {
        switch name {
        case "Real-Debrid": RealDebridView()
        case "Addons":      AddonsView()
        case "Trakt":       TraktConnectView()
        default:            AccountsView()   // TMDB & metadata keys
        }
    }

    private func statusText(_ status: SourceStatus) -> String {
        if case .error(let m) = status { return m }
        return status.label
    }
}
