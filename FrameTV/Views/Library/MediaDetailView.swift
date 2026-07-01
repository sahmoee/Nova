//
//  MediaDetailView.swift
//  FrameTV
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                Theme.Colors.appBackground.ignoresSafeArea()
                backdrop(in: geo.size)

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        Spacer(minLength: geo.size.height * 0.35)

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
                    .frame(minHeight: geo.size.height, alignment: .bottom)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .task(id: item.id) { await backfillArtIfNeeded() }
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
        // Buttons wrap to a column on compact (iPhone) so they never overflow.
        let resume = item.hasResumePoint
        VStack(spacing: Theme.Spacing.sm) {
            FocusableButton(
                title: resume ? "Resume" : "Play",
                systemImage: "play.fill",
                prominent: true,
                action: onPlay
            )
            if resume {
                FocusableButton(title: "Start Over", systemImage: "gobackward") {
                    progress.reset(for: item.id)
                    onPlay()
                }
            }
            FocusableButton(
                title: currentItem.isFavorite ? "Unfavorite" : "Favorite",
                systemImage: currentItem.isFavorite ? "star.slash" : "star"
            ) {
                library.toggleFavorite(item)
            }
            FocusableButton(
                title: currentItem.isHidden ? "Unhide" : "Hide",
                systemImage: currentItem.isHidden ? "eye" : "eye.slash"
            ) {
                library.toggleHidden(item)
            }
            // Per-show binge settings, for series only.
            if let series = item.seriesTitle ?? (item.episode != nil ? item.title : nil) {
                FocusableButton(title: "Binge Settings", systemImage: "slider.horizontal.3") {
                    bingeSeries = SeriesWrapper(value: series)
                }
            }
            FocusableButton(title: "Remove", systemImage: "trash") {
                library.remove(item)
                dismiss()
            }
        }
        .frame(maxWidth: Theme.isCompact ? .infinity : 520)
        .sheet(item: $bingeSeries) { series in
            BingeSettingsView(seriesTitle: series.value)
        }
    }

    @State private var bingeSeries: SeriesWrapper?

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
                CachedAsyncImage(url: url) { image in
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
