//
//  SmartCollection.swift
//  Astra
//
//  Rule-based collections that populate themselves from the library instead of being
//  filled by hand. A SmartRule is evaluated live against the current library, so a
//  smart collection always reflects the latest state (e.g. "Unwatched", "Added this
//  month", "Favorites").
//

import Foundation

/// A self-populating collection defined by a rule rather than a fixed item list.
struct SmartCollection: Identifiable, Hashable {
    let id: String
    let name: String
    let systemImage: String
    let rule: SmartRule

    /// The items in this smart collection, evaluated against a library snapshot.
    func items(from library: [MediaItem]) -> [MediaItem] {
        library.filter { !$0.isHidden && rule.matches($0) }
    }
}

/// A predicate over a MediaItem. Kept as an enum so it's simple and exhaustive.
enum SmartRule: Hashable {
    case unwatched              // no resume point and not finished
    case inProgress             // has a resume point, not finished
    case finished               // watched >= 90%
    case favorites
    case addedWithin(days: Int)
    case taggedAny              // has at least one tag
    case movies
    case shows

    func matches(_ item: MediaItem) -> Bool {
        switch self {
        case .unwatched:
            return item.lastPlayedPosition <= 0 && !item.isWatched
        case .inProgress:
            return item.hasResumePoint && !item.isWatched
        case .finished:
            return item.isWatched
        case .favorites:
            return item.isFavorite
        case .addedWithin(let days):
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
            return item.addedDate >= cutoff
        case .taggedAny:
            return !item.tags.isEmpty
        case .movies:
            return item.contentID?.type != .series && item.episode == nil
        case .shows:
            return item.contentID?.type == .series || item.episode != nil
        }
    }
}

extension SmartCollection {
    /// The built-in smart collections offered in the library.
    static let presets: [SmartCollection] = [
        SmartCollection(id: "smart.inprogress", name: "Continue Watching",
                        systemImage: "play.circle", rule: .inProgress),
        SmartCollection(id: "smart.unwatched", name: "Unwatched",
                        systemImage: "circle", rule: .unwatched),
        SmartCollection(id: "smart.finished", name: "Watched",
                        systemImage: "checkmark.circle", rule: .finished),
        SmartCollection(id: "smart.favorites", name: "Favorites",
                        systemImage: "heart.fill", rule: .favorites),
        SmartCollection(id: "smart.recent", name: "Added This Month",
                        systemImage: "sparkles", rule: .addedWithin(days: 30)),
        SmartCollection(id: "smart.movies", name: "Movies",
                        systemImage: "film", rule: .movies),
        SmartCollection(id: "smart.shows", name: "Shows",
                        systemImage: "tv", rule: .shows)
    ]
}
