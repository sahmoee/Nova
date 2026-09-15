//
//  MediaCard.swift
//  Nova
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
    /// Limits reactive header updates to the page that owns this card.
    var artworkScope: ArtworkHeaderScope? = nil
    /// Optional editorial position used by ranked Top Picks rails.
    var rank: Int? = nil
    /// Lets the shared card distinguish a direct playback action from opening details.
    var opensPlayback = false
    var topLeadingBadge: String? = nil
    let action: () -> Void

    @FocusState private var focused: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hovered = false
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var env: AppEnvironment

    private var width: CGFloat { widthOverride ?? (wide ? Theme.CardSize.wideWidth : Theme.CardSize.posterWidth) }
    private var height: CGFloat { heightOverride ?? (wide ? Theme.CardSize.wideHeight : Theme.CardSize.posterHeight) }
    private var active: Bool { enabled && (focused || hovered) }
    private var artworkRadius: CGFloat { wide ? Theme.Radius.card : Theme.Radius.poster }

    private var titleText: String {
        if opensPlayback { return item.displayTitle }
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
        if !subtitleText.isEmpty {
            parts.append(subtitleText)
        }
        if item.isWatched {
            parts.append("watched")
        } else if item.hasResumePoint {
            let pct = Int((item.progressFraction * 100).rounded())
            parts.append("\(pct) percent watched")
        }
        return parts.joined(separator: ", ")
    }

    private var accessibilityHint: String {
        if opensPlayback { return item.hasResumePoint ? "Resume playback. Long press for playback options." : "Start playback. Long press for playback options." }
        return quickActions ? "Open details. Long press for quick actions." : "Open details."
    }

    private var clampedProgress: Double {
        min(max(item.progressFraction, 0), 1)
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
        Button {
            if let artworkScope {
                ArtworkHeaderCoordinator.shared.select(item, in: artworkScope)
            }
            action()
        } label: {
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
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
        .scaleEffect(focused && enabled && !reduceMotion ? Theme.CardSize.focusScale : 1.0)
        // Native tvOS focus uses a clean lift and white edge without branded glow.
        .shadow(color: .black.opacity(active ? 0.35 : 0.0),
                radius: active ? 18 : 0, x: 0, y: 8)
        .animation(reduceMotion ? nil : Theme.Motion.quick, value: focused)
        .animation(reduceMotion ? nil : Theme.Motion.quick, value: hovered)
        .zIndex(active ? 1 : 0)
        #if !os(tvOS)
        .onHover { hovered = $0 }
        #endif
        .onChange(of: focused) { _, isFocused in
            // Update only the owning destination's artwork, never global chrome tint.
            if isFocused {
                if let artworkScope {
                    ArtworkHeaderCoordinator.shared.select(item, in: artworkScope)
                }
            }
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
        #if os(iOS)
        Button {
            if env.downloads.enqueue(item) != nil {
                ToastCenter.shared.show("Download started", systemImage: "arrow.down.circle.fill")
            } else if let cid = item.contentID, cid.type == .movie {
                ToastCenter.shared.show("Finding a stream to download…", systemImage: "arrow.down.circle")
                Task {
                    let ok = await env.downloadToDevice(CatalogItem(contentID: cid, title: item.displayTitle))
                    ToastCenter.shared.show(ok ? "Download started" : "No downloadable stream found",
                                            systemImage: ok ? "arrow.down.circle.fill" : "exclamationmark.triangle")
                }
            } else {
                ToastCenter.shared.show("Open this title to download an episode", systemImage: "exclamationmark.triangle")
            }
        } label: {
            Label("Download", systemImage: "arrow.down.circle")
        }
        #endif
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
                .clipShape(RoundedRectangle(cornerRadius: artworkRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: artworkRadius, style: .continuous)
                        .strokeBorder(active ? Theme.Colors.focusRing : .white.opacity(contrast == .increased ? 0.5 : 0.12),
                                      lineWidth: active ? Theme.Control.focusLineWidth : 1)
                        .allowsHitTesting(false)
                )

            if active {
                LinearGradient(colors: [.clear, .black.opacity(0.62)],
                               startPoint: .center, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: artworkRadius, style: .continuous))
                    .transition(.opacity)

                Image(systemName: opensPlayback ? "play.fill" : "info")
                    .font(.appFont(22, weight: .bold))
                    .foregroundStyle(Color.black)
                    .frame(width: 54, height: 54)
                    .background(Color.white, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.55), lineWidth: 1.5))
                    .frame(width: width, height: height, alignment: .center)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            if let topLeadingBadge {
                Text(topLeadingBadge)
                    .font(.appFont(13, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Color.black.opacity(reduceTransparency ? 1 : 0.78), in: Capsule())
                    .padding(8)
                    .frame(width: width, height: height, alignment: .topLeading)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }

            if let rank {
                Text("\(rank)")
                    .font(.appFont(wide ? 58 : 72, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.9), radius: 8, y: 3)
                    .padding(10)
                    .frame(width: width, height: height, alignment: .bottomTrailing)
                    .accessibilityHidden(true)
            }

            // Source chip + favorite marker.
            HStack(spacing: 6) {
                Image(systemName: item.sourceType.systemImage)
                    .font(.appFont(14, weight: .semibold))
                if item.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.appFont(12))
                        .foregroundStyle(Theme.Colors.warning)
                        .accessibilityHidden(true)
                }
            }
            .padding(8)
            .background {
                if reduceTransparency { Capsule().fill(Color(white: 0.14)) }
                else { Capsule().fill(.ultraThinMaterial) }
            }
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
                            .background {
                                if reduceTransparency { Circle().fill(Color(white: 0.14)) }
                                else { Circle().fill(.ultraThinMaterial) }
                            }
                            .padding(8)
                    }
                    Spacer()
                }
                .frame(width: width, height: height)
                .allowsHitTesting(false)
            } else if let quality = item.metadata.resolution, !quality.isEmpty {
                Text(quality.uppercased())
                    .font(Theme.Font.eyebrow())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background {
                        if reduceTransparency { Capsule().fill(Color(white: 0.14)) }
                        else { Capsule().fill(.ultraThinMaterial) }
                    }
                    .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.75))
                    .padding(8)
                    .frame(width: width, height: height, alignment: .topTrailing)
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
                    .fill(Theme.Colors.progressTrack)
                Rectangle()
                    .fill(Theme.Colors.progressFill)
                    .frame(width: geo.size.width * clampedProgress)
            }
        }
        .frame(height: 6)
        .clipShape(Capsule())
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .accessibilityHidden(true)
    }

    // MARK: - Title

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titleText)
                .font(Theme.Font.cardTitle())
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(2, reservesSpace: true)
            if !subtitleText.isEmpty {
                Text(subtitleText)
                    .font(.appFont(16))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.top, 4)
    }
}


// MARK: - Catalog poster card (shared)

/// The poster and two-line title card used for CatalogItems everywhere (shelf rows,
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
                .lineLimit(2, reservesSpace: true)
                .frame(width: width, alignment: .leading)
        }
        // Larger tap target: the whole card (including the gap under the poster)
        // is tappable, and VoiceOver reads it as one element.
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Open details")
    }

    private var accessibilityLabel: String {
        if let year = item.year {
            return "\(item.title), \(year)"
        }
        return item.title
    }
}
