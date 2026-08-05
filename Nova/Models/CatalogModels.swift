//
//  CatalogModels.swift
//  Nova
//
//  Models for richer catalog content introduced in Phase 3: movies and series
//  with seasons/episodes, plus a stable content identity that ties together
//  IMDB / TMDB / Trakt ids so metadata, streams, and progress can be correlated.
//

import Foundation

// MARK: - Content type

enum ContentType: String, Codable, Hashable, Sendable {
    case movie
    case series
    case tv

    var displayName: String {
        switch self {
        case .movie:  return "Movie"
        case .series: return "Series"
        case .tv:     return "Live TV"
        }
    }

    /// The path segment Stremio addons use for this type.
    var stremioPath: String { rawValue }

    /// Live content isn't resumable/scrobbled like movies and episodes.
    var isLive: Bool { self == .tv }
}

// MARK: - Content identity

/// A cross-service identity for a piece of content. Stremio addons key on IMDB
/// ids (tt…); TMDB and Trakt use their own numeric ids. We carry all we know.
struct ContentID: Codable, Hashable, Sendable {
    var imdb: String?      // e.g. "tt0903747"
    var tmdb: Int?
    var trakt: Int?
    var addonItemID: String?   // addon-specific id (live channels, custom catalogs)
    var type: ContentType

    init(imdb: String? = nil, tmdb: Int? = nil, trakt: Int? = nil,
         addonItemID: String? = nil, type: ContentType) {
        self.imdb = imdb
        self.tmdb = tmdb
        self.trakt = trakt
        self.addonItemID = addonItemID
        self.type = type
    }

    /// The id Stremio addons expect in stream/meta requests.
    /// For episodes this is suffixed by the caller (imdb:season:episode).
    var stremioBaseID: String? { imdb ?? addonItemID }

    /// A stable key for local correlation even if only one id is known.
    var stableKey: String {
        if let imdb { return "imdb:\(imdb)" }
        if let tmdb { return "tmdb:\(type.rawValue):\(tmdb)" }
        if let trakt { return "trakt:\(type.rawValue):\(trakt)" }
        if let addonItemID { return "addon:\(type.rawValue):\(addonItemID)" }
        return "unknown:\(type.rawValue)"
    }
}

// MARK: - Catalog item (a movie or a series shell)

struct CatalogItem: Identifiable, Codable, Hashable, Sendable {
    var id: String { contentID.stableKey }

    var contentID: ContentID
    var title: String
    var overview: String?
    var posterURL: URL?
    var backdropURL: URL?
    var year: Int?
    var rating: Double?          // 0...10 (TMDB/Trakt scale)
    var genres: [String]

    // Series-only. Empty for movies.
    var seasons: [SeasonInfo]

    init(
        contentID: ContentID,
        title: String,
        overview: String? = nil,
        posterURL: URL? = nil,
        backdropURL: URL? = nil,
        year: Int? = nil,
        rating: Double? = nil,
        genres: [String] = [],
        seasons: [SeasonInfo] = []
    ) {
        self.contentID = contentID
        self.title = title
        self.overview = overview
        self.posterURL = posterURL
        self.backdropURL = backdropURL
        self.year = year
        self.rating = rating
        self.genres = genres
        self.seasons = seasons
    }

    var isSeries: Bool { contentID.type == .series }

    /// Flat, ordered list of all episodes across seasons (skips specials season 0
    /// unless it's the only season present).
    var allEpisodes: [EpisodeInfo] {
        let ordered = seasons.sorted { $0.number < $1.number }
        let nonSpecials = ordered.filter { $0.number > 0 }
        let source = nonSpecials.isEmpty ? ordered : nonSpecials
        return source.flatMap { season in
            season.episodes.sorted { $0.number < $1.number }
        }
    }
}

// MARK: - Season

struct SeasonInfo: Identifiable, Codable, Hashable, Sendable {
    var id: Int { number }
    var number: Int
    var name: String?
    var episodes: [EpisodeInfo]

    init(number: Int, name: String? = nil, episodes: [EpisodeInfo] = []) {
        self.number = number
        self.name = name
        self.episodes = episodes
    }

    var displayName: String { name ?? (number == 0 ? "Specials" : "Season \(number)") }
}

// MARK: - Episode

struct EpisodeInfo: Identifiable, Codable, Hashable, Sendable {
    var id: String { "\(season)x\(number)" }
    var season: Int
    var number: Int
    var title: String?
    var overview: String?
    var stillURL: URL?
    var airDate: Date?
    var runtime: TimeInterval?

    init(
        season: Int,
        number: Int,
        title: String? = nil,
        overview: String? = nil,
        stillURL: URL? = nil,
        airDate: Date? = nil,
        runtime: TimeInterval? = nil
    ) {
        self.season = season
        self.number = number
        self.title = title
        self.overview = overview
        self.stillURL = stillURL
        self.airDate = airDate
        self.runtime = runtime
    }

    var label: String { String(format: "S%02dE%02d", season, number) }

    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        return label
    }
}


extension CatalogItem {
    /// Builds a library MediaItem for this catalog entry. AI results and other
    /// catalog-sourced titles have no concrete stream yet, so the item is marked as a
    /// Trakt-style entry whose source is resolved when the user plays it. The
    /// contentID carries the real identity so the detail screen and stream picker can
    /// resolve a playable source on demand.
    func asLibraryItem() -> MediaItem {
        let placeholder = URL(string: "nova://catalog/\(contentID.stableKey)")!
        var meta = MediaMetadata()
        meta.year = year
        return MediaItem(
            title: title,
            sourceType: .trakt,
            playbackURL: placeholder,
            posterURL: posterURL,
            backdropURL: backdropURL ?? posterURL,
            metadata: meta,
            contentID: contentID,
            seriesTitle: contentID.type == .series ? title : nil
        )
    }
}

