//
//  ContinueWatchingCard.swift
//  FrameTV
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

    var body: some View {
        MediaCard(item: item, wide: true, action: onPlay)
            .overlay(alignment: .topLeading) {
                if item.progressFraction > 0 {
                    Text("\(Int((item.progressFraction * 100).rounded()))%")
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
