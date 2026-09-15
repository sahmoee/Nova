//
//  ContinueWatchingCard.swift
//  Nova
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
        if let duration = item.duration, duration.isFinite, duration > 0 {
            let remaining = max(duration - item.lastPlayedPosition, 0)
            guard remaining.isFinite, remaining / 60 < Double(Int.max) else { return text }
            let mins = max(1, Int(ceil(remaining / 60)))
            text += mins >= 60
                ? " · \(mins / 60)h \(mins % 60)m left"
                : " · \(mins) min left"
        }
        return text
    }

    private var cardWidth: CGFloat {
        #if os(tvOS)
        return Theme.scaled(430, min: 300)
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? 320 : 224
        #endif
    }

    private var cardHeight: CGFloat {
        // Match the Apple TV landscape artwork family without stretching to 3:2.
        cardWidth * 9 / 16
    }

    var body: some View {
        MediaCard(item: item,
                  wide: true,
                  widthOverride: cardWidth,
                  heightOverride: cardHeight,
                  opensPlayback: true,
                  topLeadingBadge: progressBadge,
                  action: onPlay)
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
