//
//  CatalogShelfRow.swift
//  Astra
//
//  A horizontally-scrolling row of catalog items for one configured shelf. Loads its
//  items lazily on appear and shows a source label (Trakt / TMDB / Addon). Tapping an
//  item navigates to its detail. Used on both Home and Discover.
//

import SwiftUI

struct CatalogShelfRow: View {
    let shelf: ShelfConfig
    var showSourceLabel: Bool = true
    /// Home shows the canonical order; Discover reshuffles on every appearance.
    var variant: ShelfLoader.Variant = .home

    @EnvironmentObject private var env: AppEnvironment
    @State private var items: [CatalogItem] = []
    @State private var loaded = false

    var body: some View {
        Group {
            if !loaded || !items.isEmpty || shelf.kind.sourceLabel == "Trakt" {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    header
                    if loaded {
                        if items.isEmpty {
                            // Trakt shelves never disappear: show why they're empty so
                            // the row is always present and discoverable.
                            traktEmptyHint
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: Theme.Spacing.md) {
                                    ForEach(items) { item in
                                        NavigationLink(value: item) {
                                            posterCard(item)
                                        }
                                        .buttonStyle(FrameListRowStyle())
                                    }
                                }
                                .padding(.horizontal, Theme.Spacing.edge)
                            }
                        }
                    } else {
                        loadingRow
                    }
                }
            }
        }
        .task(id: shelf.id) {
            // Discover refreshes every time it appears so it always looks different;
            // Home loads once and keeps its ordering stable.
            if variant == .home && loaded { return }
            items = await env.shelfLoader.items(for: shelf, variant: variant)
            loaded = true
            ImageLoader.shared.prefetch(items.compactMap(\.posterURL))
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            Text(shelf.title)
                .font(Theme.Font.sectionTitle())
                .foregroundStyle(Theme.Colors.textPrimary)
            if showSourceLabel {
                Text(shelf.kind.sourceLabel.uppercased())
                    .font(.appFont(12, weight: .bold))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.white.opacity(0.08), in: Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.edge)
    }

        /// Shown when a Trakt shelf loads empty (not connected, or list empty) so the
    /// row never silently disappears from Discover or Home.
    private var traktEmptyHint: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.appFont(20))
                .foregroundStyle(Theme.Colors.textTertiary)
            Text("Connect Trakt in Settings, or add titles to this list, to fill this row.")
                .font(.appFont(15))
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.edge)
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var loadingRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.md) {
                ForEach(0..<5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(Theme.Colors.card)
                        .frame(width: Theme.CardSize.posterWidth * 0.8,
                               height: Theme.CardSize.posterWidth * 0.8 * 1.5)
                        .shimmering()
                }
            }
            .padding(.horizontal, Theme.Spacing.edge)
        }
    }

    private func posterCard(_ item: CatalogItem) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            PosterImage(url: item.posterURL,
                        width: Theme.CardSize.posterWidth * 0.8,
                        height: Theme.CardSize.posterWidth * 0.8 * 1.5)
            Text(item.title)
                .font(.appFont(17, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .frame(width: Theme.CardSize.posterWidth * 0.8, alignment: .leading)
        }
    }
}
