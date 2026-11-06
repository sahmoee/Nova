import Foundation

/// One independently merged piece of a synced library. Missing values are
/// explicit tombstones and use the same identity as the value they remove.
enum CloudLibraryRecord: Codable, Equatable, Sendable {
    case item(String, MediaItem?)
    case favorite(String, Bool?)
    case collection(UUID, CollectionHeader?)
    case membership(UUID, String, Int?)
    case watchlist(String, Int?)

    struct CollectionHeader: Codable, Equatable, Sendable {
        var name: String
        var systemImage: String
        var createdDate: Date
    }

    var identity: String {
        switch self {
        case .item(let key, _): return "item:\(key)"
        case .favorite(let key, _): return "favorite:\(key)"
        case .collection(let id, _): return "collection:\(id.uuidString)"
        case .membership(let id, let key, _): return "membership:\(id.uuidString):\(key)"
        case .watchlist(let key, _): return "watchlist:\(key)"
        }
    }

    var tombstone: Self {
        switch self {
        case .item(let key, _): return .item(key, nil)
        case .favorite(let key, _): return .favorite(key, nil)
        case .collection(let id, _): return .collection(id, nil)
        case .membership(let id, let key, _): return .membership(id, key, nil)
        case .watchlist(let key, _): return .watchlist(key, nil)
        }
    }
}
