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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                Theme.Colors.background.ignoresSafeArea()
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

                        actionButtons
                    }
                    .padding(Theme.Spacing.edge)
                    .frame(minHeight: geo.size.height, alignment: .bottom)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
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
            FocusableButton(title: "Remove", systemImage: "trash") {
                library.remove(item)
                dismiss()
            }
        }
        .frame(maxWidth: Theme.isCompact ? .infinity : 520)
    }

    // Re-read from store so favorite toggles reflect live.
    private var currentItem: MediaItem {
        library.item(id: item.id) ?? item
    }

    private func backdrop(in size: CGSize) -> some View {
        Group {
            if let url = item.backdropURL ?? item.posterURL {
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
