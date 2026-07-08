//
//  MediaCard.swift
//  Astra
//
//  Poster/wide card for a MediaItem with focus scaling and a resume progress bar.
//

import SwiftUI

struct MediaCard: View {
    let item: MediaItem
    var wide: Bool = false
    /// When true, an episode is shown as its season entry (series name + "Season N").
    var seasonGrouped: Bool = false
    /// Optional explicit dimensions that override the shared card size. Used by the
    /// Continue Watching row to show a larger, taller card without changing the size
    /// of cards in any other row.
    var widthOverride: CGFloat? = nil
    var heightOverride: CGFloat? = nil
    let action: () -> Void

    @FocusState private var focused: Bool
    @Environment(\.dynamicAccent) private var accent

    private var width: CGFloat { widthOverride ?? (wide ? Theme.CardSize.wideWidth : Theme.CardSize.posterWidth) }
    private var height: CGFloat { heightOverride ?? (wide ? Theme.CardSize.wideHeight : Theme.CardSize.posterHeight) }

    private var titleText: String {
        if seasonGrouped, item.episode != nil, let series = item.seriesTitle {
            return series
        }
        return item.title
    }

    private var subtitleText: String {
        if seasonGrouped, let ep = item.episode {
            var parts = ["Season \(ep.season)"]
            if let year = item.metadata.year { parts.append(String(year)) }
            return parts.joined(separator: " · ")
        }
        return item.subtitleLine
    }

    /// A spoken label combining the title with watched/progress context.
    private var accessibilityText: String {
        var parts = [item.displayTitle]
        if item.isWatched {
            parts.append("watched")
        } else if item.hasResumePoint {
            let pct = Int((item.progressFraction * 100).rounded())
            parts.append("\(pct) percent watched")
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                artwork
                titleBlock
            }
            .frame(width: width)
        }
        .buttonStyle(.pressable)
        .focused($focused)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .scaleEffect(focused ? Theme.CardSize.focusScale : 1.0)
        // Apple TV style: a soft black drop plus a colored glow in the artwork's accent.
        .shadow(color: .black.opacity(focused ? 0.65 : 0.0),
                radius: focused ? 28 : 0, x: 0, y: 14)
        .shadow(color: focused ? accent.opacity(0.5) : .clear,
                radius: focused ? 30 : 0, x: 0, y: 0)
        .animation(.easeOut(duration: 0.18), value: focused)
        .zIndex(focused ? 1 : 0)
        .onChange(of: focused) { _, isFocused in
            // When a card gains focus, tint the UI with its artwork color.
            if isFocused { AccentManager.shared.deriveAccent(from: item.posterURL) }
        }
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
                        .stroke(focused ? accent : Theme.Colors.separator,
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

            // Watched badge: a filled checkmark in the top-right corner once the
            // title has been fully watched. Sits over the artwork like the source
            // chip so it survives any poster.
            if item.isWatched {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .font(.appFont(18, weight: .bold))
                            .foregroundStyle(Theme.Colors.success)
                            .padding(6)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(8)
                    }
                    Spacer()
                }
                .frame(width: width, height: height)
                .allowsHitTesting(false)
            }

            // Resume progress bar.
            if item.progressFraction > 0 {
                progressBar
            }
        }
    }

    @ViewBuilder
    private var posterImage: some View {
        if let url = item.posterURL {
            CachedAsyncImage(url: url, maxPixel: 700) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                placeholder.shimmering()
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        GeneratedPoster(title: titleText, year: item.metadata.year)
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
            Text(titleText)
                .font(Theme.Font.cardTitle())
                .foregroundStyle(focused ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                .lineLimit(1)
            if !subtitleText.isEmpty {
                Text(subtitleText)
                    .font(.appFont(16))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.top, 4)
    }
}
