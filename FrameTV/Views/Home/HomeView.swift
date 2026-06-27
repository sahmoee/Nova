//
//  HomeView.swift
//  FrameTV
//
//  Apple TV-style dashboard: hero header, Continue Watching, Sources shortcut row,
//  Recently Added, and Favorites.
//

import SwiftUI

struct HomeView: View {
    @Binding var path: NavigationPath
    @EnvironmentObject private var library: LibraryStore
    @State private var selectedItem: MediaItem?

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()

                if library.items.isEmpty {
                    EmptyStateView(
                        systemImage: "play.tv",
                        title: "Welcome to FrameTV",
                        message: "Add a source or a direct link to start building your library.",
                        actionTitle: "Go to Sources",
                        action: { /* handled by tab switch in real nav; placeholder */ }
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Spacing.rowGap) {
                            header

                            MediaRow(title: "Continue Watching",
                                     items: library.continueWatching,
                                     wide: true) { play($0) }

                            sourcesShortcutRow

                            MediaRow(title: "Recently Added",
                                     items: library.recentlyAdded) { play($0) }

                            MediaRow(title: "Favorites",
                                     items: library.favorites) { play($0) }
                        }
                        .padding(.vertical, Theme.Spacing.lg)
                    }
                }
            }
            .navigationDestination(item: $selectedItem) { item in
                PlayerView(item: item)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("FrameTV")
                .font(Theme.Font.screenTitle())
                .screenTitleStyle()
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Your personal media hub")
                .font(.appFont(24))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(.horizontal, Theme.Spacing.edge)
    }

    // MARK: - Sources shortcut row

    private var sourcesShortcutRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Sources")
                .font(Theme.Font.sectionTitle())
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.leading, Theme.Spacing.edge)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.md) {
                    NavigationLink { SMBListView() } label: {
                        sourceTile("SMB Shares", "externaldrive.connected.to.line.below")
                    }.buttonStyle(.plain)

                    NavigationLink { RealDebridView() } label: {
                        sourceTile("Real-Debrid", "arrow.down.circle")
                    }.buttonStyle(.plain)

                    NavigationLink { DirectURLView() } label: {
                        sourceTile("Direct URL", "link")
                    }.buttonStyle(.plain)

                    NavigationLink { MagnetView() } label: {
                        sourceTile("Magnet Link", "scope")
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, Theme.Spacing.edge)
                .padding(.vertical, Theme.Spacing.md)
            }
        }
    }

    private func sourceTile(_ title: String, _ symbol: String) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: symbol)
                .font(.appFont(40, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent)
            Text(title)
                .font(.appFont(20, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .frame(width: Theme.CardSize.sourceWidth * 0.87, height: Theme.CardSize.sourceHeight * 0.75)
        .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.largeCard, style: .continuous))
    }

    // MARK: - Actions

    private func play(_ item: MediaItem) {
        selectedItem = item
    }
}
