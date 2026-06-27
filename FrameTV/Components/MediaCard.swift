//
//  MediaCard.swift
//  FrameTV
//
//  Poster/wide card for a MediaItem with focus scaling and a resume progress bar.
//

import SwiftUI

struct MediaCard: View {
    let item: MediaItem
    var wide: Bool = false
    let action: () -> Void

    @FocusState private var focused: Bool

    private var width: CGFloat { wide ? Theme.CardSize.wideWidth : Theme.CardSize.posterWidth }
    private var height: CGFloat { wide ? Theme.CardSize.wideHeight : Theme.CardSize.posterHeight }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                artwork
                titleBlock
            }
            .frame(width: width)
        }
        .buttonStyle(.plain)
        .focused($focused)
        .scaleEffect(focused ? Theme.CardSize.focusScale : 1.0)
        .shadow(color: .black.opacity(focused ? 0.6 : 0.0),
                radius: focused ? 24 : 0, x: 0, y: 12)
        .animation(.easeOut(duration: 0.16), value: focused)
        .zIndex(focused ? 1 : 0)
    }

    // MARK: - Artwork

    private var artwork: some View {
        ZStack(alignment: .bottomLeading) {
            posterImage
                .frame(width: width, height: height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .stroke(focused ? Theme.Colors.accent : Theme.Colors.separator,
                                lineWidth: focused ? 4 : 1)
                )

            // Source chip + favorite marker.
            HStack(spacing: 6) {
                Image(systemName: item.sourceType.systemImage)
                    .font(.appFont(14, weight: .semibold))
                if item.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.appFont(12))
                        .foregroundStyle(Theme.Colors.warning)
                }
            }
            .padding(8)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(10)

            // Resume progress bar.
            if item.progressFraction > 0 {
                progressBar
            }
        }
    }

    @ViewBuilder
    private var posterImage: some View {
        if let url = item.posterURL {
            CachedAsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                placeholder.shimmering()
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Theme.Colors.card
            Image(systemName: "film")
                .font(.appFont(44))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.black.opacity(0.5))
                Rectangle()
                    .fill(Theme.Colors.accent)
                    .frame(width: geo.size.width * item.progressFraction)
            }
        }
        .frame(height: 6)
        .clipShape(Capsule())
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    // MARK: - Title

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .font(Theme.Font.cardTitle())
                .foregroundStyle(focused ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                .lineLimit(1)
            if !item.subtitleLine.isEmpty {
                Text(item.subtitleLine)
                    .font(.appFont(16))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.top, 4)
    }
}
