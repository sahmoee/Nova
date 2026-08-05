//
//  BingeSettingsView.swift
//  Nova
//
//  Per-show binge settings. Lets a series override the global autoplay and skip
//  behavior. Each option is a tri-state: Use Default, On, or Off — so a show only
//  diverges where you want it to.
//

import SwiftUI

struct BingeSettingsView: View {
    let seriesTitle: String
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var settings: ShowSettings = .inherit

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Binge Settings")
                        .font(Theme.Font.screenTitle())
                        .screenTitleStyle()
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(seriesTitle)
                        .font(.appFont(18))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Text("Override how this show plays. Leave on Default to follow your global player settings.")
                    .font(.appFont(16))
                    .foregroundStyle(Theme.Colors.textSecondary)

                triStateRow(
                    title: "Auto-play next episode",
                    systemImage: "play.circle",
                    globalValue: env.settings.autoPlayNext,
                    binding: $settings.autoPlayNext
                )
                triStateRow(
                    title: "Skip intro",
                    systemImage: "forward.end",
                    globalValue: env.settings.skipIntroEnabled,
                    binding: $settings.skipIntro
                )
                triStateRow(
                    title: "Skip credits",
                    systemImage: "forward.frame",
                    globalValue: env.settings.skipOutroEnabled,
                    binding: $settings.skipCredits
                )
                triStateRow(
                    title: "Ask before next episode",
                    systemImage: "questionmark.circle",
                    globalValue: false,
                    binding: $settings.askBeforeNext
                )

                Button {
                    settings = .inherit
                    save()
                } label: {
                    Text("Reset to Defaults")
                        .font(.appFont(17, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                }
                .buttonStyle(.plain)
                .padding(.top, Theme.Spacing.sm)
            }
            .padding(.horizontal, Theme.Spacing.edge)
            .padding(.vertical, Theme.Spacing.xl)
            .frame(maxWidth: Theme.contentMaxWidth(800), alignment: .leading)
        }
        .background(Theme.Colors.appBackground.ignoresSafeArea())
        .onAppear { settings = env.showSettings.settings(forSeries: seriesTitle) }
        .onChange(of: settings) { _, _ in save() }
    }

    private func save() {
        env.showSettings.update(settings, forSeries: seriesTitle)
    }

    /// A row with three choices: Default (inherit), On, Off.
    private func triStateRow(title: String, systemImage: String,
                             globalValue: Bool, binding: Binding<Bool?>) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: systemImage)
                    .font(.appFont(20))
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: 30)
                Text(title)
                    .font(.appFont(18, weight: .medium))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
            }
            Picker("", selection: Binding(
                get: { TriState(from: binding.wrappedValue) },
                set: { binding.wrappedValue = $0.value }
            )) {
                Text("Default (\(globalValue ? "On" : "Off"))").tag(TriState.inherit)
                Text("On").tag(TriState.on)
                Text("Off").tag(TriState.off)
            }
            .pickerStyle(.segmented)
        }
        .padding(Theme.Spacing.md)
        .refinedCardBackground()
    }

    private enum TriState: Hashable {
        case inherit, on, off
        init(from value: Bool?) {
            switch value {
            case .none:        self = .inherit
            case .some(true):  self = .on
            case .some(false): self = .off
            }
        }
        var value: Bool? {
            switch self {
            case .inherit: return nil
            case .on:      return true
            case .off:     return false
            }
        }
    }
}
