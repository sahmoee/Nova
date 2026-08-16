//
//  PosterCollectionGrid.swift
//  Nova
//
//  A UICollectionView-backed drop-in for a poster `LazyVGrid`.
//
//  Why UIKit here: `LazyVGrid` inside a `ScrollView` keeps every realized cell's
//  view tree alive and never truly recycles, so large libraries drop frames while
//  scrolling and let decoded-image memory climb. `UICollectionView` gives real cell
//  reuse and `UICollectionViewDataSourcePrefetching`, and we prewarm posters through
//  the existing `ImageLoader` before a cell scrolls on. Each cell still hosts the
//  *exact same* SwiftUI card via `UIHostingConfiguration`, so appearance, context
//  menus, focus, and tap handling are byte-for-byte what they were in the grid.
//
//  iOS/iPadOS only. tvOS keeps `LazyVGrid` because focus movement there is driven by
//  the UIKit focus engine through SwiftUI and does not need this treatment.
//
//  Hosting gotchas handled here:
//    * Environment: `UIHostingConfiguration` does NOT inherit `@EnvironmentObject`
//      from the surrounding SwiftUI hierarchy. Inject anything your card needs
//      *inside* the `cell` closure (e.g. `card(item).environmentObject(store)`).
//    * External state: when host `@State` that a card reads (selection, edit mode)
//      changes without the item set changing, pass a new `reloadToken`. Cells are
//      reconfigured so the `cell` closure re-runs with the fresh values.
//

#if os(iOS)
import SwiftUI
import UIKit

struct PosterCollectionGrid<Item: Identifiable, Cell: View>: UIViewRepresentable where Item.ID: Hashable & Sendable {

    /// Items to render, in display order.
    let items: [Item]
    /// Minimum width per column; the layout fits as many equal columns as possible,
    /// matching `GridItem(.adaptive(minimum:))`.
    var minItemWidth: CGFloat = Theme.CardSize.posterWidth
    /// Gap between columns and rows.
    var spacing: CGFloat = Theme.Spacing.lg
    /// Padding around the whole grid (SwiftUI insets so call sites need no UIKit import).
    var sectionInsets: EdgeInsets = EdgeInsets()
    /// Bump this whenever host state a card reads (edit mode, selection) changes but
    /// `items` does not, so visible cells re-run the `cell` builder.
    var reloadToken: AnyHashable = 0
    /// Poster URL to prewarm as a cell approaches. Return nil to skip.
    var prefetchURL: (Item) -> URL? = { _ in nil }
    /// Builds the SwiftUI card for an item. Inject any required environment here.
    @ViewBuilder var cell: (Item) -> Cell

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = Self.makeLayout(minItemWidth: minItemWidth,
                                     spacing: spacing,
                                     insets: sectionInsets)
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.alwaysBounceVertical = true
        cv.keyboardDismissMode = .onDrag
        cv.contentInsetAdjustmentBehavior = .always
        cv.prefetchDataSource = context.coordinator

        let registration = UICollectionView.CellRegistration<UICollectionViewCell, Item.ID> { [weak coordinator = context.coordinator] cellView, _, id in
            guard let coordinator, let item = coordinator.item(for: id) else { return }
            cellView.contentConfiguration = UIHostingConfiguration {
                coordinator.parent.cell(item)
            }
            .margins(.all, 0)
        }

        let dataSource = UICollectionViewDiffableDataSource<Int, Item.ID>(collectionView: cv) { cv, indexPath, id in
            cv.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: id)
        }
        context.coordinator.dataSource = dataSource
        context.coordinator.apply(items: items, animatingDifferences: false)
        return cv
    }

    func updateUIView(_ cv: UICollectionView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        // Keep the layout in sync if sizing inputs changed (e.g. rotation/size class).
        cv.setCollectionViewLayout(
            Self.makeLayout(minItemWidth: minItemWidth, spacing: spacing, insets: sectionInsets),
            animated: false
        )

        let itemsChanged = coordinator.currentIDs != items.map(\.id)
        coordinator.apply(items: items, animatingDifferences: false)

        // If only host state changed (token), re-run the cell builder for existing cells.
        if !itemsChanged, coordinator.lastReloadToken != reloadToken {
            coordinator.reconfigureAll()
        }
        coordinator.lastReloadToken = reloadToken
    }

    // MARK: Layout

    /// A compositional layout whose column count is derived from the available width,
    /// reproducing `.adaptive(minimum:)` behaviour with self-sizing (estimated) height.
    private static func makeLayout(minItemWidth: CGFloat,
                                   spacing: CGFloat,
                                   insets: EdgeInsets) -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, env in
            let available = env.container.effectiveContentSize.width
                - insets.leading - insets.trailing
            let columns = max(1, Int((available + spacing) / (minItemWidth + spacing)))

            // Each repeated item owns one fraction of the row. A 1.0 fraction made
            // every cell request the whole group even when the group had 2–3 columns.
            let itemFraction = 1.0 / CGFloat(columns)
            let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(itemFraction),
                                                  heightDimension: .estimated(minItemWidth * 1.7))
            let item = NSCollectionLayoutItem(layoutSize: itemSize)

            let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                                   heightDimension: .estimated(minItemWidth * 1.7))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize,
                                                           repeatingSubitem: item,
                                                           count: columns)
            group.interItemSpacing = .fixed(spacing)

            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = spacing
            section.contentInsets = NSDirectionalEdgeInsets(top: insets.top,
                                                            leading: insets.leading,
                                                            bottom: insets.bottom,
                                                            trailing: insets.trailing)
            return section
        }
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, UICollectionViewDataSourcePrefetching {
        var parent: PosterCollectionGrid
        var dataSource: UICollectionViewDiffableDataSource<Int, Item.ID>?
        var currentIDs: [Item.ID] = []
        var lastReloadToken: AnyHashable = 0
        private var lookup: [Item.ID: Item] = [:]

        init(_ parent: PosterCollectionGrid) {
            self.parent = parent
            self.lastReloadToken = parent.reloadToken
        }

        func item(for id: Item.ID) -> Item? { lookup[id] }

        func apply(items: [Item], animatingDifferences: Bool) {
            lookup = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let ids = items.map(\.id)
            guard ids != currentIDs, let dataSource else {
                // Refresh the item lookup even when IDs are unchanged so reconfigured
                // cells see the latest item values.
                currentIDs = ids
                return
            }
            currentIDs = ids
            var snapshot = NSDiffableDataSourceSnapshot<Int, Item.ID>()
            snapshot.appendSections([0])
            snapshot.appendItems(ids, toSection: 0)
            dataSource.apply(snapshot, animatingDifferences: animatingDifferences)
        }

        func reconfigureAll() {
            guard let dataSource, !currentIDs.isEmpty else { return }
            var snapshot = dataSource.snapshot()
            snapshot.reconfigureItems(currentIDs)
            dataSource.apply(snapshot, animatingDifferences: false)
        }

        // MARK: Prefetch
        func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            let urls = indexPaths.compactMap { idx -> URL? in
                guard idx.item < currentIDs.count,
                      let item = lookup[currentIDs[idx.item]] else { return nil }
                return parent.prefetchURL(item)
            }
            if !urls.isEmpty { ImageLoader.shared.prefetch(urls) }
        }
    }
}
#endif
