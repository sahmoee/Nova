//
//  CatalogShelfRow.swift
//  Nova
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
    @EnvironmentObject private var nav: NavigationCoordinator
    @EnvironmentObject private var library: LibraryStore
    @State private var items: [CatalogItem] = []
    @State private var loaded = false

    var body: some View {
        Group {
            if !loaded || !items.isEmpty || shelf.kind.sourceLabel == "Trakt" {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    header
                    if loaded {
                        if items.isEmpty {
                            // Trakt shelves never disappear: show why they're empty.
                            traktEmptyHint
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: Theme.Spacing.md) {
                                    ForEach(items) { item in
                                        NavigationLink(value: item) {
                                            posterCard(item)
                                        }
                                        .buttonStyle(NovaListRowStyle())
                                        .contextMenu { quickActions(item) }
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
            let stale = await env.shelfLoader.cachedItems(for: shelf, variant: variant)
            if !stale.isEmpty {
                items = RecommendationFeedbackStore.shared.visible(stale) { $0.contentID.stableKey }
                loaded = true
            }
            let loadedItems = await env.shelfLoader.items(for: shelf, variant: variant)
            // Respect recommendation feedback: drop titles the user marked Not
            // Interested / Already Watched from recommendation rows.
            items = RecommendationFeedbackStore.shared.visible(loadedItems) { $0.contentID.stableKey }
            loaded = true
            ImageLoader.shared.prefetch(Array(items.prefix(16)).compactMap(\.posterURL))
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
                    // Use the shared card color instead of a magic opacity value.
                    .background(Theme.Colors.card, in: Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.edge)
    }

    /// The empty-Trakt hint is a real button now: one tap goes straight to Settings
    /// instead of describing the journey.
    private var traktEmptyHint: some View {
        Button {
            nav.selection = .settings
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.appFont(20))
                    .foregroundStyle(Theme.Colors.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect Trakt to fill this row")
                        .font(.appFont(16, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Or add titles to your Trakt list. Tap to open Settings.")
                        .font(.appFont(14))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.appFont(14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.card,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(NovaListRowStyle())
        .padding(.horizontal, Theme.Spacing.edge)
        .padding(.vertical, Theme.Spacing.sm)
    }

    /// Long-press quick actions for a catalog poster: add it to the library or the
    /// queue without opening the detail screen.
    @ViewBuilder
    private func quickActions(_ item: CatalogItem) -> some View {
        Button {
            let media = item.asLibraryItem()
            library.add(media)
            ToastCenter.shared.show("Added to Library")
        } label: {
            Label("Add to Library", systemImage: "plus.square.on.square")
        }
        Button {
            let media = item.asLibraryItem()
            library.add(media)
            library.addToQueue(media)
            ToastCenter.shared.show("Added to Queue")
        } label: {
            Label("Add to Queue", systemImage: "text.badge.plus")
        }
        #if os(iOS)
        if item.contentID.type == .movie {
            Button {
                ToastCenter.shared.show("Finding a stream to download…", systemImage: "arrow.down.circle")
                Task {
                    let ok = await env.downloadToDevice(item)
                    ToastCenter.shared.show(ok ? "Download started" : "No downloadable stream found",
                                            systemImage: ok ? "arrow.down.circle.fill" : "exclamationmark.triangle")
                }
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
        }
        #endif
    }

        private var loadingRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.md) {
                ForEach(0..<5, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .fill(Theme.Colors.card)
                            .frame(width: loadingCardWidth,
                                   height: loadingCardHeight)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.Colors.card)
                            .frame(width: loadingCardWidth * 0.68, height: 14)
                    }
                    .shimmering()
                }
            }
            .padding(.horizontal, Theme.Spacing.edge)
        }
    }

    private func posterCard(_ item: CatalogItem) -> some View {
        #if os(tvOS)
        CatalogLandscapeCard(item: item)
        #else
        CatalogPosterCard(item: item, scale: 0.8)
        #endif
    }

    private var loadingCardWidth: CGFloat {
        #if os(tvOS)
        return Theme.CardSize.wideWidth
        #else
        return Theme.CardSize.posterWidth * 0.8
        #endif
    }

    private var loadingCardHeight: CGFloat {
        #if os(tvOS)
        return Theme.CardSize.wideHeight
        #else
        return Theme.CardSize.posterWidth * 0.8 * 1.5
        #endif
    }
}

#if os(tvOS)
/// Landscape editorial card used by every tvOS shelf. It mirrors the supplied
/// reference's large 16:9 artwork, title below, and uncluttered focus treatment.
private struct CatalogLandscapeCard: View {
    let item: CatalogItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CachedAsyncImage(url: item.backdropURL ?? item.posterURL, maxPixel: 900) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                GeneratedPoster(title: item.title, year: item.year).shimmering()
            }
            .frame(width: Theme.CardSize.wideWidth, height: Theme.CardSize.wideHeight)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text(item.title)
                .font(.appFont(22, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .frame(width: Theme.CardSize.wideWidth, alignment: .leading)

            if let year = item.year {
                Text(String(year))
                    .font(.appFont(16))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
#endif
