//
//  SubtitlePickerView.swift
//  Nova
//
//  Apple-style subtitle chooser with an explicit add-on refresh action. Tracks can
//  arrive while the sheet is open, and the selected track is applied immediately.
//

import SwiftUI

struct SubtitlePickerView: View {
    let tracks: [SubtitleTrack]
    let selectedID: String?
    var isLoading: Bool = false
    var statusMessage: String? = nil
    var onRefresh: (() -> Void)? = nil
    let onSelect: (SubtitleTrack?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        if let onRefresh {
                            refreshRow(action: onRefresh)
                        }

                        row(title: "Off", subtitle: "Disable subtitles",
                            isSelected: selectedID == nil) {
                            onSelect(nil)
                            dismiss()
                        }

                        ForEach(groupedTracks, id: \.source) { group in
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                Text(group.source)
                                    .font(.appFont(15, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                    .textCase(.uppercase)
                                    .padding(.top, Theme.Spacing.sm)

                                ForEach(group.tracks) { track in
                                    row(title: track.languageDisplay,
                                        subtitle: track.isEmbedded ? "Embedded" : "Download and use",
                                        isSelected: track.id == selectedID) {
                                        onSelect(track)
                                        dismiss()
                                    }
                                }
                            }
                        }

                        if tracks.isEmpty && !isLoading {
                            Text("No subtitles are loaded yet. Search enabled subtitle add-ons to find available tracks.")
                                .font(.appFont(17))
                                .foregroundStyle(Theme.Colors.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, Theme.Spacing.md)
                        }

                        if let statusMessage, !statusMessage.isEmpty {
                            Text(statusMessage)
                                .font(.appFont(15))
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .padding(.top, Theme.Spacing.xs)
                        }
                    }
                    .padding(Theme.Spacing.edge)
                    .frame(maxWidth: Theme.contentMaxWidth(900), alignment: .leading)
                }
            }
            .navigationTitle("Audio & Subtitles")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    private var groupedTracks: [(source: String, tracks: [SubtitleTrack])] {
        let grouped = Dictionary(grouping: tracks) { track in
            track.source.isEmpty ? "Subtitles" : track.source
        }
        return grouped.keys.sorted().map { source in
            let sorted = (grouped[source] ?? []).sorted {
                $0.languageDisplay.localizedCaseInsensitiveCompare($1.languageDisplay) == .orderedAscending
            }
            return (source, sorted)
        }
    }

    private func refreshRow(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                if isLoading {
                    ProgressView()
                        .tint(Theme.Colors.textPrimary)
                        .frame(width: 30)
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.appFont(27))
                        .foregroundStyle(Theme.Colors.accent)
                        .frame(width: 30)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(isLoading ? "Searching Subtitle Add-ons…" : "Download from Add-ons")
                        .font(.appFont(20, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Search enabled providers for this movie or episode")
                        .font(.appFont(15))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
            }
            .padding(Theme.Spacing.md)
            .background(.thinMaterial,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(NovaListRowStyle())
        .disabled(isLoading)
    }

    private func row(title: String, subtitle: String?, isSelected: Bool,
                     action: @escaping () -> Void) -> some View {
        Button {
            // Success haptic when a subtitle choice is applied (no-op on tvOS).
            Haptics.play(.success)
            action()
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.textSecondary)
                    .font(.appFont(25))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.appFont(20, weight: .medium))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.appFont(14))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
                Spacer()
            }
            .padding(Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(isSelected ? Theme.Colors.accent.opacity(0.16) : Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(isSelected ? Theme.Colors.accent : Color.white.opacity(0.08),
                                  lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(NovaListRowStyle())
    }
}
