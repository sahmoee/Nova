//
//  ContinueWatchingCard.swift
//  Astra
//
//  A MediaCard wrapper for the Continue Watching row that adds a resume-percentage
//  badge and a context menu with Restart and Remove, so the user can manage their
//  in-progress items directly from the shelf.
//

import SwiftUI

struct ContinueWatchingCard: View {
    let item: MediaItem
    var onPlay: () -> Void
    var onRestart: () -> Void
    var onRemove: () -> Void

    /// "48% · 32 min left" — percent plus real time remaining when the duration is
    /// known, so the card answers "how much is left?" at a glance.
    private var progressBadge: String? {
        guard item.progressFraction > 0 else { return nil }
        var text = "\(Int((item.progressFraction * 100).rounded()))%"
        if let duration = item.duration, duration > 0 {
            let remaining = max(duration - item.lastPlayedPosition, 0)
            let mins = max(1, Int((remaining / 60).rounded()))
            text += mins >= 60
                ? " · \(mins / 60)h \(mins % 60)m left"
                : " · \(mins) min left"
        }
        return text
    }

    var body: some View {
        MediaCard(item: item,
                  wide: true,
                  widthOverride: Theme.scaled(430, min: 300),
                  heightOverride: Theme.scaled(300, min: 200),
                  action: onPlay)
            .overlay(alignment: .topLeading) {
                if let badge = progressBadge {
                    Text(badge)
                        .font(.appFont(13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.black.opacity(0.6), in: Capsule())
                        .padding(Theme.Spacing.sm)
                }
            }
            .contextMenu {
                Button(action: onPlay) {
                    Label(item.hasResumePoint ? "Resume" : "Play", systemImage: "play.fill")
                }
                Button(action: onRestart) {
                    Label("Start Over", systemImage: "gobackward")
                }
                Button(role: .destructive, action: onRemove) {
                    Label("Remove from Continue Watching", systemImage: "xmark.circle")
                }
            }
    }
}
