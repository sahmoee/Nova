//
//  HomeShelf.swift
//  FrameTV
//
//  Defines the catalog "shelves" the user can show on Home and Discover, and a
//  store that persists which are enabled and in what order. Each shelf knows how to
//  load its items (Trakt, TMDB, or an addon catalog) and carries a source label.
//

import Foundation
import Combine

/// A kind of shelf the app can render. Each case maps to a data source.
enum ShelfKind: Codable, Hashable {
    case traktWatchlist
    case traktTrendingShows
    case tmdbTrending          // movies
    case tmdbTrendingShows
    case tmdbPopularMovies
    case tmdbNowPlaying        // "In Theaters"
    case tmdbTopRated
    case tmdbPopularShows
    case tmdbAiringToday
    case addonCatalog(addonID: UUID, type: String, catalogID: String)

    var defaultTitle: String {
        switch self {
        case .traktWatchlist:     return "Your Trakt Watchlist"
        case .traktTrendingShows: return "Trending Shows on Trakt"
        case .tmdbTrending:       return "Trending Movies"
        case .tmdbTrendingShows:  return "Trending Shows"
        case .tmdbPopularMovies:  return "Popular Movies"
        case .tmdbNowPlaying:     return "In Theaters"
        case .tmdbTopRated:       return "Top Rated Movies"
        case .tmdbPopularShows:   return "Popular Shows"
        case .tmdbAiringToday:    return "On TV Today"
        case .addonCatalog:       return "Addon Catalog"
        }
    }

    /// Short source label shown under/next to the shelf title on Discover.
    var sourceLabel: String {
        switch self {
        case .traktWatchlist, .traktTrendingShows: return "Trakt"
        case .addonCatalog:                        return "Addon"
        default:                                   return "TMDB"
        }
    }

    /// Whether this shelf needs a Trakt login.
    var requiresTrakt: Bool {
        switch self {
        case .traktWatchlist: return true
        default: return false
        }
    }

    /// Whether this shelf needs a TMDB key.
    var requiresTMDB: Bool {
        switch self {
        case .traktWatchlist, .traktTrendingShows, .addonCatalog: return false
        default: return true
        }
    }
}

/// A configured shelf: its kind, a display title, and whether it's enabled.
struct ShelfConfig: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var kind: ShelfKind
    var title: String
    var isEnabled: Bool

    init(kind: ShelfKind, title: String? = nil, isEnabled: Bool = true) {
        self.kind = kind
        self.title = title ?? kind.defaultTitle
        self.isEnabled = isEnabled
    }
}

/// Persists the user's shelf selection/order. Defaults to a sensible starter set.
/// Syncs across devices in real time via iCloud key-value storage.
@MainActor
final class HomeShelfStore: ObservableObject {
    static let shared = HomeShelfStore()

    @Published var shelves: [ShelfConfig] {
        didSet { persist() }
    }

    private let key = "home.shelves.v1"
    private var isApplyingRemote = false
    private var cancellable: AnyCancellable?

    private init() {
        // Prefer an iCloud value, then a local one, then defaults.
        if let data = CloudSync.shared.data(forKey: key) ?? UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([ShelfConfig].self, from: data),
           !decoded.isEmpty {
            shelves = decoded
        } else {
            shelves = HomeShelfStore.defaults
        }

        // Apply changes made on other devices in real time.
        cancellable = CloudSync.shared.externalChange
            .receive(on: RunLoop.main)
            .sink { [weak self] changedKeys in
                guard let self, changedKeys.contains(self.key) else { return }
                guard let data = CloudSync.shared.data(forKey: self.key),
                      let decoded = try? JSONDecoder().decode([ShelfConfig].self, from: data)
                else { return }
                self.isApplyingRemote = true
                self.shelves = decoded
                self.isApplyingRemote = false
            }
    }

    static var defaults: [ShelfConfig] {
        [
            ShelfConfig(kind: .traktWatchlist),
            ShelfConfig(kind: .tmdbTrending),
            ShelfConfig(kind: .tmdbTrendingShows),
            ShelfConfig(kind: .tmdbNowPlaying),
            ShelfConfig(kind: .tmdbPopularShows, isEnabled: false),
            ShelfConfig(kind: .tmdbTopRated, isEnabled: false),
        ]
    }

    var enabledShelves: [ShelfConfig] { shelves.filter(\.isEnabled) }

    func move(from: IndexSet, to: Int) { shelves.move(fromOffsets: from, toOffset: to) }

    func setEnabled(_ enabled: Bool, for id: UUID) {
        guard let idx = shelves.firstIndex(where: { $0.id == id }) else { return }
        shelves[idx].isEnabled = enabled
    }

    func resetToDefaults() { shelves = HomeShelfStore.defaults }

    private func persist() {
        // Don't write back a change we just received from iCloud (avoids a loop).
        guard !isApplyingRemote else { return }
        if let data = try? JSONEncoder().encode(shelves) {
            UserDefaults.standard.set(data, forKey: key)
            CloudSync.shared.setData(data, forKey: key)
            CloudSync.shared.flush()
        }
    }
}
