//
//  SubtitlePickerView.swift
//  FrameTV
//
//  A sheet to choose a subtitle track (or turn them off), grouped by source.
//

import SwiftUI

struct SubtitlePickerView: View {
    let tracks: [SubtitleTrack]
    let selectedID: String?
    let onSelect: (SubtitleTrack?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Subtitles")
                        .font(Theme.Font.screenTitle())
                        .screenTitleStyle()
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .padding(.bottom, Theme.Spacing.sm)

                    row(title: "Off", subtitle: nil, isSelected: selectedID == nil) {
                        onSelect(nil); dismiss()
                    }

                    ForEach(tracks) { track in
                        row(title: track.languageDisplay,
                            subtitle: track.source,
                            isSelected: track.id == selectedID) {
                            onSelect(track); dismiss()
                        }
                    }

                    if tracks.isEmpty {
                        Text("No subtitles found for this title.")
                            .font(.appFont(20))
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .padding(.top, Theme.Spacing.md)
                    }
                }
                .padding(Theme.Spacing.edge)
                .frame(maxWidth: Theme.contentMaxWidth(900), alignment: .leading)
            }
        }
    }

    private func row(title: String, subtitle: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.textSecondary)
                    .font(.appFont(26))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.appFont(22, weight: .medium))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.appFont(16))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
                Spacer()
            }
            .padding(Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(isSelected
                          ? AnyShapeStyle(Theme.Colors.accent.opacity(0.16))
                          : AnyShapeStyle(Theme.Colors.cardGradient))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(isSelected ? Theme.Colors.accent : Color.white.opacity(0.06),
                                  lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(FrameListRowStyle())
    }
}
