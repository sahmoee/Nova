//
//  HomeShelf.swift
//  Nova
//
//  Defines the catalog "shelves" the user can show on Home and Discover, and a
//  store that persists which are enabled and in what order. Each shelf knows how to
//  load its items (Trakt, TMDB, or an addon catalog) and carries a source label.
//

import Foundation
import Combine

/// A kind of shelf the app can render. Each case maps to a data source.
enum ShelfKind: Codable, Hashable, Sendable {
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
    case aiShelf(prompt: String)

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
        case .aiShelf(let prompt): return prompt.isEmpty ? "AI Shelf" : prompt.capitalized
        }
    }

    /// Short source label shown under/next to the shelf title on Discover.
    var sourceLabel: String {
        switch self {
        case .traktWatchlist, .traktTrendingShows: return "Trakt"
        case .addonCatalog:                        return "Addon"
        case .aiShelf:                             return "AI"
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

    /// Stable identity for caching this shelf's contents (in-memory, on disk, and
    /// anywhere else a per-shelf key is needed).
    var cacheKey: String {
        switch self {
        case .traktWatchlist:     return "traktWatchlist"
        case .traktTrendingShows: return "traktTrendingShows"
        case .tmdbTrending:       return "tmdbTrending"
        case .tmdbTrendingShows:  return "tmdbTrendingShows"
        case .tmdbPopularMovies:  return "tmdbPopularMovies"
        case .tmdbNowPlaying:     return "tmdbNowPlaying"
        case .tmdbTopRated:       return "tmdbTopRated"
        case .tmdbPopularShows:   return "tmdbPopularShows"
        case .tmdbAiringToday:    return "tmdbAiringToday"
        case .addonCatalog(let a, let t, let c): return "addon:\(a):\(t):\(c)"
        case .aiShelf(let prompt): return "ai:\(prompt)"
        }
        // NOTE: never use String(describing:) here — this type conforms to
        // CustomStringConvertible via cacheKey, so that would recurse infinitely.
        // The literal names above match the previous String(describing:) output,
        // keeping existing on-disk cache keys valid.
    }
}

extension ShelfKind: CustomStringConvertible {
    var description: String { cacheKey }
}

/// A configured shelf: its kind, a display title, and whether it's enabled. The
/// Omni-style layout adds per-shelf card layout, Top Row pinning and an item cap.
struct ShelfConfig: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var kind: ShelfKind
    var title: String
    var isEnabled: Bool
    /// Card layout for this row; nil follows the platform default.
    var layout: OmniShelfLayout?
    /// Pinned shelves form the Top Row directly under the Home hero.
    var isPinnedToTopRow: Bool = false
    /// Maximum items shown in the row; nil shows everything the source returns.
    var itemLimit: Int?

    init(kind: ShelfKind, title: String? = nil, isEnabled: Bool = true,
         layout: OmniShelfLayout? = nil, isPinnedToTopRow: Bool = false, itemLimit: Int? = nil) {
        self.kind = kind
        self.title = title ?? kind.defaultTitle
        self.isEnabled = isEnabled
        self.layout = layout
        self.isPinnedToTopRow = isPinnedToTopRow
        self.itemLimit = itemLimit
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, title, isEnabled, layout, isPinnedToTopRow, itemLimit
    }

    // Older saved shelves and iCloud mirrors predate the layout fields.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decode(ShelfKind.self, forKey: .kind)
        title = try c.decode(String.self, forKey: .title)
        isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        layout = try? c.decodeIfPresent(OmniShelfLayout.self, forKey: .layout)
        isPinnedToTopRow = (try? c.decodeIfPresent(Bool.self, forKey: .isPinnedToTopRow)) ?? false
        itemLimit = (try? c.decodeIfPresent(Int.self, forKey: .itemLimit)).flatMap { $0 }.map { min(max($0, 5), 100) }
    }

    /// Whether the shelf's source returns movies, series, or a mix.
    var contentType: ContentType? {
        switch kind {
        case .tmdbTrending, .tmdbPopularMovies, .tmdbNowPlaying, .tmdbTopRated: return .movie
        case .tmdbTrendingShows, .tmdbPopularShows, .tmdbAiringToday, .traktTrendingShows: return .series
        case .addonCatalog(_, let type, _):
            switch type { case "movie": return .movie; case "series": return .series; default: return nil }
        case .traktWatchlist, .aiShelf: return nil
        }
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

    private let backing = CloudBackedStore<[ShelfConfig]>(key: PrefKey.homeShelves)
    private var isApplyingRemote = false
    private var cancellable: AnyCancellable?

    private init() {
        shelves = HomeShelfStore.defaults
        loadPreferences()

        // Preference resets are domain events rather than writes to this exact
        // key, so listen for both before applying a replacement shelf list.
        cancellable = CloudSync.shared.externalChange
            .receive(on: RunLoop.main)
            .sink { [weak self] keys in
                if keys.contains(PrefKey.homeShelves) || keys.contains(SettingsDataDomain.preferences.deletionKey) {
                    self?.loadPreferences()
                }
            }
        NotificationCenter.default.addObserver(
            forName: .novaBackupRestored, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reloadFromPreferences() }
        }
    }

    /// The Settings reset/Pull already changed the local preferences. Prefer that
    /// authoritative copy and cancel any shelf edit queued before the operation.
    func reloadFromPreferences() {
        backing.cancelPendingPush()
        loadPreferences(preferLocal: true)
    }

    private func loadPreferences(preferLocal: Bool = false) {
        let cloud = CloudSync.shared
        if cloud.consumeDeletion(.preferences, consumer: ".homeShelves") {
            backing.cancelPendingPush()
            UserDefaults.standard.removeObject(forKey: PrefKey.homeShelves)
        }
        let local = UserDefaults.standard.data(forKey: PrefKey.homeShelves)
            .flatMap { try? Coders.decoder.decode([ShelfConfig].self, from: $0) }
        let decoded = preferLocal ? (local ?? backing.load()) : (backing.load() ?? local)
        isApplyingRemote = true
        shelves = decoded ?? HomeShelfStore.defaults
        isApplyingRemote = false
    }

    static var defaults: [ShelfConfig] {
        [
            ShelfConfig(kind: .tmdbTrending),
            ShelfConfig(kind: .tmdbTrendingShows),
            ShelfConfig(kind: .tmdbNowPlaying),
            ShelfConfig(kind: .tmdbPopularShows, isEnabled: false),
            ShelfConfig(kind: .tmdbTopRated, isEnabled: false),
        ]
    }

    var enabledShelves: [ShelfConfig] {
        shelves.filter { shelf in
            guard shelf.isEnabled else { return false }
            switch shelf.kind {
            case .traktWatchlist, .traktTrendingShows: return false
            default: return true
            }
        }
    }

    func move(from: IndexSet, to: Int) { shelves.move(fromOffsets: from, toOffset: to) }

    func setEnabled(_ enabled: Bool, for id: UUID) {
        guard let idx = shelves.firstIndex(where: { $0.id == id }) else { return }
        shelves[idx].isEnabled = enabled
    }

    func resetToDefaults() { shelves = HomeShelfStore.defaults }

    /// Applies an edit to one shelf (rename, layout, Top Row pin, item cap).
    func update(_ id: UUID, _ change: (inout ShelfConfig) -> Void) {
        guard let idx = shelves.firstIndex(where: { $0.id == id }) else { return }
        change(&shelves[idx])
    }

    /// Moves one shelf up (-1) or down (+1), for remote-friendly reordering.
    func move(id: UUID, offset: Int) {
        guard let idx = shelves.firstIndex(where: { $0.id == id }) else { return }
        let target = idx + offset
        guard shelves.indices.contains(target) else { return }
        shelves.swapAt(idx, target)
    }

    /// Shelves shown in the Home Top Row. Falls back to the first enabled shelf so
    /// the hero always has a source.
    var topRowShelves: [ShelfConfig] {
        let pinned = enabledShelves.filter(\.isPinnedToTopRow)
        return pinned.isEmpty ? Array(enabledShelves.prefix(1)) : pinned
    }

    /// Enabled shelves below the Top Row.
    var remainingShelves: [ShelfConfig] {
        let top = Set(topRowShelves.map(\.id))
        return enabledShelves.filter { !top.contains($0.id) }
    }

    private func persist() {
        // Don't write back a change we just received from iCloud (avoids a loop).
        guard !isApplyingRemote else { return }
        // Local write is immediate; the iCloud push is debounced by the backing
        // store so reorder/toggle bursts produce one network write.
        backing.persist(shelves)
    }
}
