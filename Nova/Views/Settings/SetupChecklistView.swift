//
//  SetupChecklistView.swift
//  Nova
//
//  A guided setup checklist that walks a new user through configuring Nova: the
//  TMDB key (for artwork and details), Real-Debrid, Trakt, addons, SMB, and choosing
//  a player. Each step shows whether it's done (from SourceHealth) and links to where
//  to set it up. Reachable from Settings and surfaced on Home when nothing is set up.
//

import SwiftUI

struct SetupChecklistView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    /// Re-read health when returning from a sub-screen.
    @State private var refresh = false

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    header
                    progressSummary
                    VStack(spacing: Theme.Spacing.sm) {
                        ForEach(steps) { step in
                            stepRow(step)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.edge)
                }
                .padding(.bottom, Theme.Spacing.xl)
                .id(refresh)   // force re-evaluation of step states
            }
        }
        .navigationTitle("Setup")
        .onAppear { refresh.toggle() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Set Up Nova")
                .font(Theme.Font.screenTitle())
                .screenTitleStyle()
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Connect your own accounts and sources. Only the movie database key is required; everything else is optional but unlocks more.")
                .font(.appFont(18))
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(maxWidth: 640, alignment: .leading)
        }
        .padding(.horizontal, Theme.Spacing.edge)
        .padding(.top, Theme.Spacing.lg)
    }

    private var progressSummary: some View {
        let done = steps.filter(\.isDone).count
        let total = steps.count
        return HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: done == total ? "checkmark.seal.fill" : "list.bullet.clipboard")
                .foregroundStyle(done == total ? Theme.Colors.success : Theme.Colors.accent)
            Text("\(done) of \(total) set up")
                .font(.appFont(18, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .padding(Theme.Spacing.md)
        .refinedCardBackground()
        .padding(.horizontal, Theme.Spacing.edge)
    }

    private func stepRow(_ step: Step) -> some View {
        NavigationLink {
            step.destination
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: step.isDone ? "checkmark.circle.fill" : step.systemImage)
                    .font(.appFont(26))
                    .foregroundStyle(step.isDone ? Theme.Colors.success : Theme.Colors.accent)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(step.title)
                            .font(.appFont(20, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        if step.required {
                            Text("Required")
                                .font(.appFont(12, weight: .bold))
                                .foregroundStyle(Theme.Colors.warning)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Theme.Colors.warning.opacity(0.16), in: Capsule())
                        }
                    }
                    Text(step.isDone ? (step.doneDetail ?? "Done") : step.subtitle)
                        .font(.appFont(15))
                        .foregroundStyle(step.isDone ? Theme.Colors.success : Theme.Colors.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(Theme.Spacing.md)
            .refinedCardBackground()
        }
        .novaRowStyle()
    }

    // MARK: - Steps

    private struct Step: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let systemImage: String
        let required: Bool
        let isDone: Bool
        var doneDetail: String?
        let destination: AnyView
    }

    private var steps: [Step] {
        let tmdb = SourceHealth.tmdb()
        let rd = SourceHealth.realDebrid()
        let trakt = SourceHealth.trakt()
        let addons = SourceHealth.addons(env.addonStore)

        return [
            Step(id: "tmdb",
                 title: "Add Movie Database Key",
                 subtitle: "Required for posters, descriptions, and episodes",
                 systemImage: "photo.on.rectangle",
                 required: true,
                 isDone: tmdb.status == .connected,
                 doneDetail: "Connected",
                 destination: AnyView(AccountsView())),
            Step(id: "rd",
                 title: "Connect Real-Debrid",
                 subtitle: "For cloud streaming of your own content",
                 systemImage: "arrow.down.circle",
                 required: false,
                 isDone: rd.status == .connected,
                 doneDetail: "Connected",
                 destination: AnyView(RealDebridView())),
            Step(id: "trakt",
                 title: "Connect Trakt",
                 subtitle: "For your watchlist and trending lists",
                 systemImage: "checkmark.seal",
                 required: false,
                 isDone: trakt.status == .connected,
                 doneDetail: "Connected",
                 destination: AnyView(TraktConnectView())),
            Step(id: "addons",
                 title: "Install Addons",
                 subtitle: "Add catalog and stream sources",
                 systemImage: "puzzlepiece.extension",
                 required: false,
                 isDone: addons.status == .connected,
                 doneDetail: addons.detail,
                 destination: AnyView(AddonsView())),
            Step(id: "smb",
                 title: "Add an SMB Share",
                 subtitle: "Stream from a computer on your network",
                 systemImage: "externaldrive.connected.to.line.below",
                 required: false,
                 isDone: false,   // SMB share count isn't surfaced here; always actionable
                 destination: AnyView(SMBListView())),
            Step(id: "player",
                 title: "Choose Your Player",
                 subtitle: "Pick the built-in or an external player",
                 systemImage: "play.rectangle",
                 required: false,
                 isDone: false,   // always optional/visitable
                 destination: AnyView(PlayerSettingsView()))
        ]
    }
}
