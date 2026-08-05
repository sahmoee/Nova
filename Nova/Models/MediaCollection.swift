//
//  MediaCollection.swift
//  Nova
//
//  A user-created collection (folder) of library items, organized by intent — e.g.
//  "Halloween", "Comfort Shows", "For Shalise". Distinct from Favorites, which is a
//  single flat flag. Collections reference items by their stable content key so they
//  survive re-adds and sync across devices.
//

import Foundation

struct MediaCollection: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var systemImage: String
    /// Stable content keys of the items in this collection, in insertion order.
    var contentKeys: [String]
    var createdDate: Date

    init(id: UUID = UUID(),
         name: String,
         systemImage: String = "rectangle.stack",
         contentKeys: [String] = [],
         createdDate: Date = Date()) {
        self.id = id
        self.name = name
        self.systemImage = systemImage
        self.contentKeys = contentKeys
        self.createdDate = createdDate
    }

    var count: Int { contentKeys.count }
}
