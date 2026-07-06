//
//  AstraTopShelf.swift
//  AstraTopShelf (tvOS Top Shelf extension target)
//
//  Shows Continue Watching and Recently Added rows on the Apple TV home screen, above
//  the Astra icon. Reads the same App Group snapshot the app writes for widgets, so
//  no extra app-side work is needed. Selecting an item opens Astra via a frametv://
//  deep link.
//
//  IMPORTANT — Xcode setup (see TOPSHELF_SETUP.md):
//   • This file belongs to the AstraTopShelf extension target only (tvOS).
//   • WidgetShared.swift must be a member of this target too (it holds the snapshot model).
//   • This target and the tvOS app must both enable App Group "group.com.frametv.shared".
//

import TVServices

final class ContentProvider: TVTopShelfContentProvider {

    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        let snapshot = WidgetShared.read()

        var sections: [TVTopShelfItemCollection<TVTopShelfSectionedItem>] = []

        if !snapshot.continueWatching.isEmpty {
            sections.append(collection(title: "Continue Watching", entries: snapshot.continueWatching))
        }
        if !snapshot.recentlyAdded.isEmpty {
            sections.append(collection(title: "Recently Added", entries: snapshot.recentlyAdded))
        }

        guard !sections.isEmpty else {
            completionHandler(nil)
            return
        }

        let content = TVTopShelfSectionedContent(sections: sections)
        completionHandler(content)
    }

    private func collection(title: String,
                            entries: [WidgetEntry]) -> TVTopShelfItemCollection<TVTopShelfSectionedItem> {
        let items: [TVTopShelfSectionedItem] = entries.map { entry in
            let item = TVTopShelfSectionedItem(identifier: entry.id)
            item.title = entry.title
            if let poster = entry.posterURL {
                // Poster aspect for the home-screen row.
                item.setImageURL(poster, for: .screenScale1x)
                item.setImageURL(poster, for: .screenScale2x)
            }
            item.imageShape = .poster
            // Selecting the item opens the app to this title.
            if let url = URL(string: entry.deepLink) {
                item.displayAction = TVTopShelfAction(url: url)
                item.playAction = TVTopShelfAction(url: url)
            }
            return item
        }

        let collection = TVTopShelfItemCollection(items: items)
        collection.title = title
        return collection
    }
}
