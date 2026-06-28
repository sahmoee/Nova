//
//  FeaturedHero.swift
//  FrameTV
//
//  An Apple TV-style featured banner for the top of the Home screen. It spotlights a
//  single item with a large backdrop, a gradient scrim, the title and a short line of
//  metadata, and a Play button. While shown, it tints the app accent with the item's
//  artwork color so the whole dashboard takes on its mood.
//

import SwiftUI

struct FeaturedHero: View {
    let item: MediaItem
    var onPlay: (MediaItem) -> Void

    @Environment(\.dynamicAccent) private var accent
    @FocusState private var playFocused: Bool

    var body: some View {
        GeometryReader { geo in
            heroContent(width: geo.size.width)
        }
        // A sensible fixed height that scales with the platform; on iPhone this keeps
        // the hero to roughly a third of a typical screen instead of dominating it.
        .frame(height: heroHeight)
    }

    /// Hero height tuned per platform. iPhone/iPad get a compact banner; tvOS gets the
    /// full cinematic height.
    private var heroHeight: CGFloat {
        #if os(tvOS)
        return 560
        #else
        // Cap to a comfortable banner height on handhelds.
        return Theme.isCompact ? 230 : 380
        #endif
    }

    private func heroContent(width: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Backdrop (falls back to poster).
            CachedAsyncImage(url: item.backdropURL ?? item.posterURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(Theme.Colors.card)
            }
            .frame(width: width, height: heroHeight)
            .clipped()

            // Scrims + accent wash.
            LinearGradient(
                colors: [.clear, Theme.Colors.background.opacity(0.55), Theme.Colors.background],
                startPoint: .top, endPoint: .bottom
            )
            LinearGradient(
                colors: [Theme.Colors.background.opacity(0.85), .clear],
                startPoint: .leading, endPoint: .trailing
            )
            LinearGradient(
                colors: [accent.opacity(0.32), .clear],
                startPoint: .bottomLeading, endPoint: .topTrailing
            )
            .blendMode(.plusLighter)

            // Foreground content.
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(item.displayTitle)
                    .font(.system(size: Theme.scaledFont(44), weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 2)

                if !item.subtitleLine.isEmpty {
                    Text(item.subtitleLine)
                        .font(.appFont(18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }

                Button { onPlay(item) } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "play.fill")
                        Text(item.hasResumePoint ? "Resume" : "Play")
                            .fontWeight(.semibold)
                    }
                    .font(.appFont(18))
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(playFocused ? accent : .white, in: Capsule())
                    .foregroundStyle(playFocused ? .white : .black)
                    .scaleEffect(playFocused ? 1.06 : 1.0)
                    .shadow(color: playFocused ? accent.opacity(0.5) : .clear,
                            radius: playFocused ? 20 : 0, y: 6)
                    .animation(.easeOut(duration: 0.18), value: playFocused)
                }
                .buttonStyle(.plain)
                .focused($playFocused)
                .padding(.top, 2)
            }
            .padding(.horizontal, Theme.Spacing.edge)
            .padding(.bottom, Theme.Spacing.md)
        }
        .frame(width: width, height: heroHeight)
        .clipped()
        .onAppear { AccentManager.shared.deriveAccent(from: item.posterURL ?? item.backdropURL) }
    }
}
