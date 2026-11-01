//
//  OmniRows.swift
//  Nova
//
//  Omni-style catalog rows: a plain section title over a horizontally scrolling run
//  of poster (2:3) or landscape (16:9) cards. Rows honor the global poster size and
//  "always show titles" settings plus each shelf's own layout and item cap.
//

import SwiftUI

/// Section title used by every Omni-style row.
struct OmniRowHeader: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.appFont(OmniStyle.rowTitleSize, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(.appFont(OmniStyle.rowTitleSize * 0.62, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, OmniStyle.edge)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Platform default when a shelf has no explicit layout: tvOS leads with posters
/// like Omni's catalog rows, touch platforms likewise.
extension ShelfConfig {
    var resolvedLayout: OmniShelfLayout { layout ?? .poster }
}

/// One configured catalog shelf, loaded through `ShelfLoader`.
struct OmniShelfRow: View {
    let shelf: ShelfConfig
    var compact: Bool = false
    var variant: ShelfLoader.Variant = .home
    /// Called when a card gains focus (tvOS) so the page can retint its backdrop.
    var onFocusItem: ((CatalogItem) -> Void)? = nil
    /// Reports the loaded items, e.g. so Home can feed its hero from the Top Row.
    var onLoaded: (([CatalogItem]) -> Void)? = nil

    @EnvironmentObject private var env: AppEnvironment
    @State private var items: [CatalogItem] = []
    @State private var loaded = false

    var body: some View {
        if !loaded || !items.isEmpty {
            OmniCatalogRow(title: shelf.title,
                           items: visibleItems,
                           layout: shelf.resolvedLayout,
                           compact: compact,
                           isLoading: !loaded,
                           onFocusItem: onFocusItem)
                .task(id: shelf) { await load() }
        }
    }

    private var visibleItems: [CatalogItem] {
        guard let limit = shelf.itemLimit else { return items }
        return Array(items.prefix(limit))
    }

    private func load() async {
        if variant == .home && loaded { return }
        let cached = await env.shelfLoader.cachedItems(for: shelf, variant: variant)
        if !cached.isEmpty {
            items = RecommendationFeedbackStore.shared.visible(cached) { $0.contentID.stableKey }
            loaded = true
            onLoaded?(items)
        }
        let fresh = await env.shelfLoader.items(for: shelf, variant: variant)
        guard !Task.isCancelled else { return }
        items = RecommendationFeedbackStore.shared.visible(fresh) { $0.contentID.stableKey }
        loaded = true
        onLoaded?(items)
        ImageLoader.shared.prefetch(Array(visibleItems.prefix(12)).compactMap {
            shelf.resolvedLayout == .landscape ? ($0.backdropURL ?? $0.posterURL) : $0.posterURL
        })
    }
}

/// A titled row of catalog cards. Navigation pushes `CatalogItem` values, so the
/// host stack must register a destination for them.
struct OmniCatalogRow: View {
    let title: String
    let items: [CatalogItem]
    var layout: OmniShelfLayout = .poster
    var compact: Bool = false
    var isLoading: Bool = false
    var onFocusItem: ((CatalogItem) -> Void)? = nil

    @AppStorage(OmniLayoutKey.posterSize) private var posterSizeRaw = OmniPosterSize.medium.rawValue
    @EnvironmentObject private var library: LibraryStore

    private var size: OmniPosterSize {
        let base = OmniPosterSize(rawValue: posterSizeRaw) ?? .medium
        return compact ? .small : base
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            OmniRowHeader(title: title)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: OmniStyle.cardSpacing) {
                    if isLoading && items.isEmpty {
                        ForEach(0..<6, id: \.self) { _ in placeholder }
                    } else {
                        ForEach(items) { item in
                            NavigationLink(value: item) {
                                OmniCatalogCard(item: item, layout: layout, size: size)
                            }
                            .buttonStyle(OmniCardButtonStyle())
                            .onFocusChange { if $0 { onFocusItem?(item) } }
                            .contextMenu { quickActions(item) }
                        }
                    }
                }
                .padding(.horizontal, OmniStyle.edge)
                .padding(.vertical, 18)
            }
            .scrollClipDisabled()
        }
    }

    private var placeholder: some View {
        let width = layout == .landscape ? OmniStyle.landscapeWidth(size) : OmniStyle.posterWidth(size)
        let height = layout == .landscape ? width * 9 / 16 : width * 1.5
        return RoundedRectangle(cornerRadius: OmniStyle.cardRadius, style: .continuous)
            .fill(Theme.Colors.card)
            .frame(width: width, height: height)
            .shimmering()
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func quickActions(_ item: CatalogItem) -> some View {
        Button {
            library.add(item.asLibraryItem())
            ToastCenter.shared.show("Added to Library")
        } label: {
            Label("Add to Library", systemImage: "plus")
        }
        Button {
            let media = item.asLibraryItem()
            library.add(media)
            library.addToQueue(media)
            ToastCenter.shared.show("Added to Up Next")
        } label: {
            Label("Add to Up Next", systemImage: "text.badge.plus")
        }
    }
}

/// Poster or landscape artwork with the title beneath. Titles are always visible on
/// touch platforms; on tvOS they appear on focus unless "Always Show Titles" is on.
struct OmniCatalogCard: View {
    let item: CatalogItem
    let layout: OmniShelfLayout
    let size: OmniPosterSize

    @AppStorage(OmniLayoutKey.alwaysShowTitles) private var alwaysShowTitles = false
    @Environment(\.isFocused) private var focused

    private var width: CGFloat {
        layout == .landscape ? OmniStyle.landscapeWidth(size) : OmniStyle.posterWidth(size)
    }
    private var height: CGFloat { layout == .landscape ? width * 9 / 16 : width * 1.5 }
    private var artworkURL: URL? {
        layout == .landscape ? (item.backdropURL ?? item.posterURL) : (item.posterURL ?? item.backdropURL)
    }

    private var showsTitle: Bool {
        #if os(tvOS)
        alwaysShowTitles || focused || layout == .landscape
        #else
        true
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CachedAsyncImage(url: artworkURL, maxPixel: layout == .landscape ? 900 : 600) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                GeneratedPoster(title: item.title, year: item.year)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: OmniStyle.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: OmniStyle.cardRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.06), lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.appFont(titleSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let year = item.year {
                    Text(String(year))
                        .font(.appFont(titleSize * 0.8))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .frame(width: width, alignment: .leading)
            .opacity(showsTitle ? 1 : 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([item.title, item.year.map(String.init)].compactMap { $0 }.joined(separator: ", "))
    }

    private var titleSize: CGFloat {
        #if os(tvOS)
        22
        #else
        Theme.isPad ? 15 : 13
        #endif
    }
}

extension View {
    /// Reports focus changes for a focusable view on every platform. On touch
    /// platforms focus only moves with a keyboard, so this is rarely called there.
    func onFocusChange(_ action: @escaping (Bool) -> Void) -> some View {
        modifier(OmniFocusChangeModifier(action: action))
    }
}

private struct OmniFocusChangeModifier: ViewModifier {
    let action: (Bool) -> Void
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .onChange(of: focused) { _, value in action(value) }
    }
}
