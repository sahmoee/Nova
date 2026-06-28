//
//  WhatsNewView.swift
//  FrameTV
//
//  Presents the highlights for a release. Shown automatically after an update and
//  reachable any time from Settings.
//

import SwiftUI

struct WhatsNewView: View {
    let note: ReleaseNote
    var onDismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("What's New")
                        .font(Theme.Font.screenTitle())
                        .screenTitleStyle()
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Version \(note.version) · \(note.headline)")
                        .font(.appFont(20))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    ForEach(note.features) { feature in
                        HStack(alignment: .top, spacing: Theme.Spacing.md) {
                            Image(systemName: feature.symbol)
                                .font(.appFont(30, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Theme.Colors.accent)
                                .frame(width: Theme.scaled(46, min: 34), alignment: .center)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(feature.title)
                                    .font(.appFont(22, weight: .bold))
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Text(feature.detail)
                                    .font(.appFont(18))
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                FocusableButton(title: "Continue", systemImage: "checkmark", prominent: true) {
                    onDismiss()
                }
                .frame(maxWidth: Theme.isCompact ? .infinity : 360)
                .padding(.top, Theme.Spacing.md)
            }
            .padding(Theme.Spacing.edge)
            .frame(maxWidth: Theme.contentMaxWidth(900), alignment: .leading)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
    }
}
