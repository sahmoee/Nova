//
//  PlayerSettingsView.swift
//  FrameTV
//
//  Lets the user pick how video plays: which built-in engine/profile to use, or
//  whether to hand playback off to an external app (iOS only) like Infuse or VLC.
//

import SwiftUI

struct PlayerSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("Player")
                    .font(Theme.Font.screenTitle())
                    .screenTitleStyle()
                    .foregroundStyle(Theme.Colors.textPrimary)

                // Built-in players.
                Text("Built-in Player")
                    .font(Theme.Font.sectionTitle())
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("How video plays inside FrameTV. Automatic picks the best engine for each file.")
                    .font(.appFont(16))
                    .foregroundStyle(Theme.Colors.textSecondary)

                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(BuiltInPlayer.allCases) { player in
                        choiceRow(
                            title: player.title,
                            detail: player.detail,
                            systemImage: player.systemImage,
                            isSelected: settings.builtInPlayer == player && !externalActive
                        ) {
                            settings.builtInPlayer = player
                            #if os(iOS)
                            settings.useExternalPlayer = false
                            #endif
                        }
                    }
                }

                #if os(iOS)
                Divider().padding(.vertical, Theme.Spacing.sm)

                // External players.
                Text("External Player")
                    .font(Theme.Font.sectionTitle())
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Hand video to another app you have installed. FrameTV opens the stream there instead of playing it in-app.")
                    .font(.appFont(16))
                    .foregroundStyle(Theme.Colors.textSecondary)

                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(ExternalPlayer.allCases) { player in
                        choiceRow(
                            title: player.title,
                            detail: installedDetail(for: player),
                            systemImage: player.systemImage,
                            isSelected: settings.useExternalPlayer && settings.preferredExternalPlayer == player
                        ) {
                            settings.preferredExternalPlayer = player
                            settings.useExternalPlayer = true
                        }
                    }
                }

                Text("Auto Sleep Timer")
                    .font(.appFont(22, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.top, Theme.Spacing.md)
                Text("Automatically start a sleep timer whenever playback begins. You can still adjust it from the player.")
                    .font(.appFont(16))
                    .foregroundStyle(Theme.Colors.textTertiary)
                Picker("Auto Sleep Timer", selection: $settings.autoSleepMinutes) {
                    ForEach(SleepTimer.Preset.allCases) { preset in
                        Text(preset.label).tag(preset.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Text("External players are opened by their app's link. If an app isn't installed, FrameTV will offer to play in-app instead.")
                    .font(.appFont(14))
                    .foregroundStyle(Theme.Colors.textTertiary)
                #endif

                Divider().padding(.vertical, Theme.Spacing.sm)

                // Playback speed.
                Text("Playback Speed")
                    .font(Theme.Font.sectionTitle())
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Default speed for playback. Applies to the built-in players.")
                    .font(.appFont(16))
                    .foregroundStyle(Theme.Colors.textSecondary)

                HStack(spacing: Theme.Spacing.sm) {
                    ForEach([0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { speed in
                        Button {
                            settings.playbackSpeed = speed
                        } label: {
                            Text(speed == 1.0 ? "1×" : "\(speedLabel(speed))×")
                                .font(.appFont(17, weight: .semibold))
                                .foregroundStyle(settings.playbackSpeed == speed ? Theme.Colors.background : Theme.Colors.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Theme.Spacing.sm)
                                .background(settings.playbackSpeed == speed ? Theme.Colors.accent : Theme.Colors.card,
                                            in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.edge)
            .padding(.vertical, Theme.Spacing.xl)
            .frame(maxWidth: Theme.contentMaxWidth(1000), alignment: .leading)
        }
        .background(Theme.Colors.appBackground.ignoresSafeArea())
    }

    /// Formats a speed for display (e.g. 1.25 -> "1.25", 1.5 -> "1.5").
    private func speedLabel(_ speed: Double) -> String {
        let s = String(format: "%.2f", speed)
        // Trim trailing zeros: 1.50 -> 1.5, 1.00 -> 1
        var trimmed = s
        while trimmed.hasSuffix("0") { trimmed.removeLast() }
        if trimmed.hasSuffix(".") { trimmed.removeLast() }
        return trimmed
    }

    private var externalActive: Bool {
        #if os(iOS)
        return settings.useExternalPlayer
        #else
        return false
        #endif
    }

    #if os(iOS)
    private func installedDetail(for player: ExternalPlayer) -> String {
        player.isInstalled ? player.detail : "\(player.detail) (not installed)"
    }
    #endif

    private func choiceRow(title: String, detail: String, systemImage: String,
                           isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: systemImage)
                    .font(.appFont(22))
                    .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.textSecondary)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.appFont(20, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(detail)
                        .font(.appFont(15))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Theme.Spacing.sm)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.appFont(24))
                    .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.textTertiary)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .refinedCardBackground()
            .contentShape(Rectangle())
        }
        .buttonStyle(FrameListRowStyle())
    }
}
