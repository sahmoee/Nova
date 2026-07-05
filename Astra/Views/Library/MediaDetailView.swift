//
//  MediaDetailView.swift
//  Astra
//
//  Detail sheet for a library item: backdrop, metadata, and actions
//  (Play / Resume, Start Over, Favorite, Remove).
//

import SwiftUI

struct MediaDetailView: View {
    let item: MediaItem
    let onPlay: () -> Void

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var progress: PlaybackProgressStore
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicAccent) private var accent

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                Theme.Colors.appBackground.ignoresSafeArea()
                backdrop(in: geo.size)

                ScrollView {
                    switch settings.detailStyle {
                    case .cinematic: cinematicContent(in: geo.size)
                    case .classic:   classicContent(in: geo.size)
                    }
                }
            }
        }
        .task(id: item.id) { await backfillArtIfNeeded() }
        // Sheets are attached once at the body level so each presentation binding has
        // exactly one owner. Duplicating them per layout branch caused "only
        // presenting a single sheet is supported" warnings and dropped presentations.
        .sheet(item: $bingeSeries) { series in
            BingeSettingsView(seriesTitle: series.value)
        }
        .sheet(isPresented: $showFixMatch) {
            FixMatchView(item: item)
                .environmentObject(env)
                .environmentObject(library)
        }
    }

    // MARK: - Classic layout (original)

    private func classicContent(in size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Spacer(minLength: size.height * 0.35)

            Text(item.title)
                .font(Theme.Font.screenTitle())
                .screenTitleStyle()
                .foregroundStyle(Theme.Colors.textPrimary)

            if !item.subtitleLine.isEmpty {
                Text(item.subtitleLine)
                    .font(.appFont(24))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            metadataChips

            playbackMemoryNote

            actionButtons
        }
        .padding(Theme.Spacing.edge)
        .frame(minHeight: size.height, alignment: .bottom)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Cinematic layout (glass card + tile grid)

    private func cinematicContent(in size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: size.height * 0.30)

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text(item.title)
                    .font(Theme.Font.screenTitle())
                    .screenTitleStyle()
                    .foregroundStyle(Theme.Colors.textPrimary)

                // Year / episode line plus a source badge capsule.
                HStack(spacing: Theme.Spacing.sm) {
                    if !item.subtitleLine.isEmpty {
                        Text(item.subtitleLine)
                            .font(.appFont(20))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text("•")
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: item.sourceType.systemImage)
                        Text(item.sourceType.displayName)
                    }
                    .font(.appFont(16, weight: .semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 6)
                    .overlay(Capsule().strokeBorder(accent.opacity(0.5), lineWidth: 1))
                }

                metadataChips

                playbackMemoryNote

                // Full-width primary Play / Resume.
                FocusableButton(
                    title: item.hasResumePoint ? "Resume" : "Play",
                    systemImage: "play.fill",
                    prominent: true,
                    action: onPlay
                )
                .frame(maxWidth: .infinity)
                .padding(.top, Theme.Spacing.xs)

                if item.hasResumePoint {
                    FocusableButton(title: "Start Over", systemImage: "gobackward") {
                        progress.reset(for: item.id)
                        onPlay()
                    }
                    .frame(maxWidth: .infinity)
                }

                // Compact horizontal rail of secondary actions (small buttons, not
                // stacked). Scrolls if they exceed the width.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.sm) {
                        compactAction(currentItem.isFavorite ? "Unfavorite" : "Favorite",
                                      systemImage: currentItem.isFavorite ? "star.slash" : "star") {
                            library.toggleFavorite(item)
                        }
                        compactAction(library.isQueued(item) ? "In Queue" : "Queue",
                                      systemImage: library.isQueued(item) ? "text.badge.checkmark" : "text.badge.plus") {
                            library.isQueued(item) ? library.removeFromQueue(item) : library.addToQueue(item)
                        }
                        compactAction(currentItem.isHidden ? "Unhide" : "Hide",
                                      systemImage: currentItem.isHidden ? "eye" : "eye.slash") {
                            library.toggleHidden(item)
                        }
                        if let series = item.seriesTitle ?? (item.episode != nil ? item.title : nil) {
                            compactAction("Binge", systemImage: "slider.horizontal.3") {
                                bingeSeries = SeriesWrapper(value: series)
                            }
                        }
                        compactAction("Fix Match", systemImage: "wand.and.stars") {
                            showFixMatch = true
                        }
                        compactAction("Remove", systemImage: "trash", destructive: true) {
                            library.remove(item)
                            dismiss()
                        }
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                }
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card * 1.5, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card * 1.5, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .frame(minHeight: size.height, alignment: .bottom)
    }

    /// A compact horizontal action button: icon over a short label in a small pill.
    private func compactAction(_ title: String, systemImage: String,
                               destructive: Bool = false,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.appFont(20, weight: .semibold))
                Text(title)
                    .font(.appFont(14, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(destructive ? Theme.Colors.error : Theme.Colors.textPrimary)
            .frame(minWidth: 78)
            .padding(.vertical, Theme.Spacing.sm)
            .padding(.horizontal, Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(destructive ? AnyShapeStyle(Theme.Colors.error.opacity(0.12)) : AnyShapeStyle(Theme.Colors.cardGradient))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(destructive ? Theme.Colors.error.opacity(0.35) : Color.white.opacity(0.07), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(FrameListRowStyle())
    }

    /// A secondary action tile: accent icon, bold title, muted subtitle.
    private func actionTile(_ title: String, subtitle: String, systemImage: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: systemImage)
                    .font(.appFont(24, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.appFont(18, weight: .bold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(subtitle)
                        .font(.appFont(14))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
            .refinedCardBackground()
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(FrameListRowStyle())
    }

    /// Older library items (added before episodes used show art) may have an episode
    /// still as their poster, or no art at all. When such an item is opened, fetch the
    /// show's proper poster/backdrop from TMDB once and update it in the library so the
    /// grid and detail screens show clean artwork.
    private func backfillArtIfNeeded() async {
        let it = currentItem
        // Only episodes, only when we can identify the show on TMDB and have a key.
        guard it.episode != nil, let tmdb = it.contentID?.tmdb, env.tmdb.hasKey else { return }
        // Fetch the show's canonical poster/backdrop and adopt them if they differ from
        // what's stored (older items may hold an episode still instead of show art).
        guard let art = try? await env.tmdb.artwork(tmdbID: tmdb, isMovie: false) else { return }
        var updated = it
        var changed = false
        if let poster = art.poster, updated.posterURL != poster { updated.posterURL = poster; changed = true }
        if let backdrop = art.backdrop, updated.backdropURL != backdrop { updated.backdropURL = backdrop; changed = true }
        if changed { library.update(updated) }
    }

    @ViewBuilder
    private var actionButtons: some View {
        let resume = item.hasResumePoint
        return VStack(spacing: Theme.Spacing.sm) {
            FocusableButton(
                title: resume ? "Resume" : "Play",
                systemImage: "play.fill",
                prominent: true,
                action: onPlay
            )
            .frame(maxWidth: Theme.isCompact ? .infinity : 520)

            // Secondary actions as a compact horizontal rail of small buttons.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    if resume {
                        compactAction("Start Over", systemImage: "gobackward") {
                            progress.reset(for: item.id); onPlay()
                        }
                    }
                    compactAction(library.isQueued(item) ? "In Queue" : "Queue",
                                  systemImage: library.isQueued(item) ? "text.badge.checkmark" : "text.badge.plus") {
                        library.isQueued(item) ? library.removeFromQueue(item) : library.addToQueue(item)
                    }
                    compactAction(currentItem.isFavorite ? "Unfavorite" : "Favorite",
                                  systemImage: currentItem.isFavorite ? "star.slash" : "star") {
                        library.toggleFavorite(item)
                    }
                    compactAction(currentItem.isHidden ? "Unhide" : "Hide",
                                  systemImage: currentItem.isHidden ? "eye" : "eye.slash") {
                        library.toggleHidden(item)
                    }
                    if let series = item.seriesTitle ?? (item.episode != nil ? item.title : nil) {
                        compactAction("Binge", systemImage: "slider.horizontal.3") {
                            bingeSeries = SeriesWrapper(value: series)
                        }
                    }
                    compactAction("Fix Match", systemImage: "wand.and.stars") {
                        showFixMatch = true
                    }
                    compactAction("Remove", systemImage: "trash", destructive: true) {
                        library.remove(item); dismiss()
                    }
                }
                .padding(.vertical, Theme.Spacing.xs)
            }
        }
        .frame(maxWidth: Theme.isCompact ? .infinity : 520)
    }

    @State private var bingeSeries: SeriesWrapper?
    @State private var showFixMatch = false

    // Re-read from store so favorite toggles reflect live.
    private var currentItem: MediaItem {
        library.item(id: item.id) ?? item
    }

    private func backdrop(in size: CGSize) -> some View {
        // Use the show's backdrop (16:9, fills the wide hero well) or its poster as a
        // fallback. Episode stills are deliberately avoided - they're cropped frames
        // that look wrong zoomed to fill the screen.
        let heroURL = currentItem.backdropURL ?? currentItem.posterURL
        return Group {
            if let url = heroURL {
                CachedAsyncImage(url: url, maxPixel: 1600) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Theme.Colors.card.shimmering()
                }
            } else {
                Theme.Colors.heroGradient
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .overlay(
            LinearGradient(
                colors: [.clear, Theme.Colors.background.opacity(0.6), Theme.Colors.background],
                startPoint: .top, endPoint: .bottom
            )
        )
        .ignoresSafeArea()
    }

    private var metadataChips: some View {
        HStack(spacing: Theme.Spacing.sm) {
            chip(item.sourceType.displayName, systemImage: item.sourceType.systemImage)
            if let res = item.metadata.resolution { chip(res) }
            if let codec = item.metadata.codec { chip(codec) }
            if let size = item.metadata.fileSize {
                chip(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
            }
        }
    }

    /// Shows which engine last played this title successfully, so the user knows what
    /// to expect (and can choose the right engine up front rather than after a failure).
    @ViewBuilder
    private var playbackMemoryNote: some View {
        if let engine = PlayerMemory.engine(for: item) {
            let name = engine == .vlc ? "VLC" : "Apple Player"
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.Colors.success)
                Text("Last played successfully with \(name)")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .font(.appFont(16))
        }
    }

    private func chip(_ text: String, systemImage: String? = nil) -> some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.appFont(18, weight: .medium))
        .foregroundStyle(Theme.Colors.textSecondary)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

/// Wraps a series title so it can drive a sheet(item:) presentation.
private struct SeriesWrapper: Identifiable, Equatable {
    let value: String
    var id: String { value }
}
