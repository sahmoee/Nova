//
//  LibraryCleanupView.swift
//  FrameTV
//
//  Surfaces titles the user started but seems to have abandoned, with gentle actions:
//  keep (dismiss from this list), clear progress, archive (hide), or restart. Nothing
//  is deleted automatically — the user is always in control.
//

import SwiftUI

struct LibraryCleanupView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var progress: PlaybackProgressStore

    /// Items the user has dismissed ("keep") this session, so they drop off the list.
    @State private var kept: Set<UUID> = []

    private var abandoned: [MediaItem] {
        LibraryCleanup.abandoned(in: library.items).filter { !kept.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("Tidy Up")
                    .font(Theme.Font.screenTitle())
                    .screenTitleStyle()
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Titles you started a while ago and haven't finished. Clear what you're done with — nothing is removed unless you say so.")
                    .font(.appFont(16))
                    .foregroundStyle(Theme.Colors.textSecondary)

                if abandoned.isEmpty {
                    VStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "sparkles")
                            .font(.appFont(52))
                            .foregroundStyle(Theme.Colors.accent)
                        Text("All caught up")
                            .font(.appFont(22, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("Nothing's been left unfinished for long.")
                            .font(.appFont(17))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, Theme.Spacing.xl)
                } else {
                    VStack(spacing: Theme.Spacing.md) {
                        ForEach(abandoned) { item in
                            cleanupRow(item)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.edge)
            .padding(.vertical, Theme.Spacing.xl)
            .frame(maxWidth: Theme.contentMaxWidth(900), alignment: .leading)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
    }

    private func cleanupRow(_ item: MediaItem) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.md) {
                poster(item)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.seriesTitle ?? item.title)
                        .font(.appFont(19, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    Text("\(Int(item.progressFraction * 100))% watched · last played \(LibraryCleanup.staleness(item))")
                        .font(.appFont(14))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
            }
            // Actions
            HStack(spacing: Theme.Spacing.sm) {
                actionButton("Keep", icon: "checkmark") { kept.insert(item.id) }
                actionButton("Clear Progress", icon: "gobackward") {
                    library.clearProgress(for: item.id)
                    progress.reset(for: item.id)
                }
                actionButton("Archive", icon: "archivebox") {
                    library.toggleHidden(item)
                }
                actionButton("Remove", icon: "trash", destructive: true) {
                    library.remove(item)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .refinedCardBackground()
    }

    private func poster(_ item: MediaItem) -> some View {
        Group {
            if let url = item.posterURL {
                CachedAsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Theme.Colors.background.shimmering()
                }
            } else {
                RoundedRectangle(cornerRadius: 6).fill(Theme.Colors.background)
                    .overlay(Image(systemName: "film").foregroundStyle(Theme.Colors.textTertiary))
            }
        }
        .frame(width: 52, height: 78)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func actionButton(_ label: String, icon: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.appFont(14, weight: .medium))
            .foregroundStyle(destructive ? Theme.Colors.error : Theme.Colors.accent)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 6)
            .background(Theme.Colors.background, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
