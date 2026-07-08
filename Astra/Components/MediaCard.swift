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
    /// Continue Watching row to show a larger card without changing other rows.
    var widthOverride: CGFloat? = nil
    var heightOverride: CGFloat? = nil
    /// When true, long-press offers Play / Queue / Favorite / Watched / Hide without
    /// opening the detail screen. Off by default so rows that attach their own
    /// context menus (Continue Watching, collections) are unaffected.
    var quickActions: Bool = false
    let action: () -> Void

    @FocusState private var focused: Bool
    @Environment(\.dynamicAccent) private var accent
    @EnvironmentObject private var library: LibraryStore

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

    @ViewBuilder
    var body: some View {
        if quickActions {
            core.contextMenu { quickMenu }
        } else {
            core
        }
    }

    private var core: some View {
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

    // MARK: - Quick actions

    @ViewBuilder private var quickMenu: some View {
        Button(action: action) {
            Label(item.hasResumePoint ? "Resume" : "Play", systemImage: "play.fill")
        }
        Button {
            if library.isQueued(item) {
                library.removeFromQueue(item)
                ToastCenter.shared.show("Removed from Queue")
            } else {
                library.addToQueue(item)
                ToastCenter.shared.show("Added to Queue")
            }
        } label: {
            Label(library.isQueued(item) ? "Remove from Queue" : "Add to Queue",
                  systemImage: "text.badge.plus")
        }
        Button {
            library.toggleFavorite(item)
            Haptics.selection()
        } label: {
            Label(item.isFavorite ? "Remove Favorite" : "Favorite",
                  systemImage: item.isFavorite ? "star.slash" : "star")
        }
        Button {
            if item.isWatched { library.markUnwatched(item) } else { library.markWatched(item) }
            Haptics.selection()
        } label: {
            Label(item.isWatched ? "Mark Unwatched" : "Mark Watched",
                  systemImage: item.isWatched ? "checkmark.circle.badge.xmark" : "checkmark.circle")
        }
        Button(role: .destructive) {
            library.toggleHidden(item)
            ToastCenter.shared.show("Hidden from your rows")
        } label: {
            Label("Hide", systemImage: "eye.slash")
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

    private var artworkURL: URL? {
        // Wide cards (Continue Watching) look best with a landscape backdrop; fall
        // back to the poster when no backdrop is available.
        if wide { return item.backdropURL ?? item.posterURL }
        return item.posterURL
    }

    @ViewBuilder
    private var posterImage: some View {
        if let url = artworkURL {
            CachedAsyncImage(url: url, maxPixel: 700) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()
            } placeholder: {
                placeholder
                    .shimmering()
                    .frame(width: width, height: height)
            }
        } else {
            placeholder
                .frame(width: width, height: height)
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


// MARK: - Catalog poster card (shared)

/// The poster + one-line-title card used for CatalogItems everywhere (shelf rows,
/// AI results, search grids), so sizing and typography stay identical.
struct CatalogPosterCard: View {
    let item: CatalogItem
    var scale: CGFloat = 1.0

    private var width: CGFloat { Theme.CardSize.posterWidth * scale }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            PosterImage(url: item.posterURL,
                        width: width,
                        height: width * 1.5,
                        title: item.title,
                        year: item.year)
            Text(item.title)
                .font(.appFont(17, weight: .medium))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
        }
    }
}
