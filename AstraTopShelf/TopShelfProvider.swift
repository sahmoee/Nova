//
//  TopShelfProvider.swift
//  AstraTopShelf
//
//  tvOS Top Shelf extension. Surfaces Continue Watching and Recently Added on the
//  Apple TV home screen when Astra is the top row, and deep-links straight into the
//  app. It reads the same shared App Group snapshot the widgets use, so it shows only
//  the user's own library, never any public catalog.
//

import TVServices
import Foundation

final class TopShelfProvider: NSObject, TVTopShelfContentProvider {

    private static let appGroup = "group.com.frametv.shared"
    private static let snapshotFile = "widget_snapshot.json"

    func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        let snapshot = readSnapshot()

        var sections: [TVTopShelfItemCollection<TVTopShelfSectionedItem>] = []

        let continueItems = snapshot.continueWatching.map { makeItem($0) }
        if !continueItems.isEmpty {
            let collection = TVTopShelfItemCollection(items: continueItems)
            collection.title = "Continue Watching"
            sections.append(collection)
        }

        let recentItems = snapshot.recentlyAdded.map { makeItem($0) }
        if !recentItems.isEmpty {
            let collection = TVTopShelfItemCollection(items: recentItems)
            collection.title = "Recently Added"
            sections.append(collection)
        }

        guard !sections.isEmpty else {
            completionHandler(nil)
            return
        }

        let content = TVTopShelfSectionedContent(sections: sections)
        completionHandler(content)
    }

    private func makeItem(_ entry: SharedEntry) -> TVTopShelfSectionedItem {
        let item = TVTopShelfSectionedItem(identifier: entry.id)
        item.title = entry.title
        if let poster = entry.posterURL {
            item.setImageURL(poster, for: .screenScale1x)
            item.setImageURL(poster, for: .screenScale2x)
        }
        item.imageShape = .poster
        if let url = URL(string: entry.deepLink) {
            item.displayAction = TVTopShelfAction(url: url)
            item.playAction = TVTopShelfAction(url: url)
        }
        return item
    }

    // MARK: - Shared snapshot (mirrors the app's WidgetShared model)

    private struct SharedSnapshot: Codable {
        var continueWatching: [SharedEntry]
        var recentlyAdded: [SharedEntry]
    }

    private struct SharedEntry: Codable {
        var id: String
        var title: String
        var subtitle: String
        var posterURLString: String?
        var progress: Double
        var deepLink: String
        var posterURL: URL? { posterURLString.flatMap(URL.init(string:)) }
    }

    private func readSnapshot() -> SharedSnapshot {
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup)?
            .appendingPathComponent(Self.snapshotFile),
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(SharedSnapshot.self, from: data)
        else {
            return SharedSnapshot(continueWatching: [], recentlyAdded: [])
        }
        return snapshot
    }
}
