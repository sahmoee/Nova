//
//  MetadataModels.swift
//  Astra
//
//  Codable models for TMDB (metadata/artwork) and Trakt (lists, scrobble,
//  watched state). Only the fields Astra uses are included.
//

import Foundation

// MARK: - TMDB

struct TMDBSearchResponse<T: Codable>: Codable {
    let results: [T]
}

struct TMDBMovie: Codable {
    let id: Int
    let title: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let voteAverage: Double?
    let genreIds: [Int]?
    let imdbId: String?         // present on detail fetch

    enum CodingKeys: String, CodingKey {
        case id, title, overview
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case releaseDate = "release_date"
        case voteAverage = "vote_average"
        case genreIds = "genre_ids"
        case imdbId = "imdb_id"
    }

    var year: Int? { releaseDate.flatMap { Int($0.prefix(4)) } }
}

struct TMDBShow: Codable {
    let id: Int
    let name: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let firstAirDate: String?
    let voteAverage: Double?
    let genreIds: [Int]?
    let numberOfSeasons: Int?
    let seasons: [TMDBSeason]?

    enum CodingKeys: String, CodingKey {
        case id, name, overview, seasons
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
        case genreIds = "genre_ids"
        case numberOfSeasons = "number_of_seasons"
    }

    var year: Int? { firstAirDate.flatMap { Int($0.prefix(4)) } }
}

struct TMDBSeason: Codable {
    let seasonNumber: Int?
    let name: String?
    let episodeCount: Int?

    enum CodingKeys: String, CodingKey {
        case name
        case seasonNumber = "season_number"
        case episodeCount = "episode_count"
    }
}

struct TMDBSeasonDetail: Codable {
    let seasonNumber: Int?
    let name: String?
    let episodes: [TMDBEpisode]?

    enum CodingKeys: String, CodingKey {
        case name, episodes
        case seasonNumber = "season_number"
    }
}

struct TMDBEpisode: Codable {
    let episodeNumber: Int?
    let seasonNumber: Int?
    let name: String?
    let overview: String?
    let stillPath: String?
    let airDate: String?
    let runtime: Int?

    enum CodingKeys: String, CodingKey {
        case name, overview, runtime
        case episodeNumber = "episode_number"
        case seasonNumber = "season_number"
        case stillPath = "still_path"
        case airDate = "air_date"
    }
}

struct TMDBExternalIDs: Codable {
    let imdbId: String?
    enum CodingKeys: String, CodingKey { case imdbId = "imdb_id" }
}

/// Response from TMDB's /find/{external_id} endpoint, used to resolve an IMDB id to a
/// TMDB id. Only the id of the first matching result is needed.
struct TMDBFindResponse: Codable {
    struct Match: Codable { let id: Int }
    let movieResults: [Match]
    let tvResults: [Match]
    enum CodingKeys: String, CodingKey {
        case movieResults = "movie_results"
        case tvResults = "tv_results"
    }
}

/// Minimal detail payload used to fetch artwork for a TMDB id (e.g. enriching Trakt
/// rows, which have ids but no images).
struct TMDBArtworkDetail: Codable {
    let posterPath: String?
    let backdropPath: String?
    enum CodingKeys: String, CodingKey {
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
    }
}

/// TMDB /videos response, used to find a trailer for the detail screen.
struct TMDBVideosResponse: Codable {
    let results: [TMDBVideo]
}

struct TMDBVideo: Codable {
    let key: String        // YouTube/Vimeo key
    let site: String       // "YouTube", "Vimeo"
    let type: String       // "Trailer", "Teaser", "Clip", ...
    let official: Bool

    enum CodingKeys: String, CodingKey {
        case key, site, type, official
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        site = (try? c.decode(String.self, forKey: .site)) ?? ""
        type = (try? c.decode(String.self, forKey: .type)) ?? ""
        official = (try? c.decode(Bool.self, forKey: .official)) ?? false
    }
}

/// Helpers for building TMDB image URLs.
enum TMDBImage {
    static let base = "https://image.tmdb.org/t/p/"
    static func poster(_ path: String?) -> URL? { url(path, size: "w780") }
    static func backdrop(_ path: String?) -> URL? { url(path, size: "original") }
    static func still(_ path: String?) -> URL? { url(path, size: "w780") }
    static func profile(_ path: String?) -> URL? { url(path, size: "w300") }

    private static func url(_ path: String?, size: String) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: base + size + path)
    }
}

// MARK: - Trakt

struct TraktDeviceCode: Codable {
    let deviceCode: String
    let userCode: String
    let verificationUrl: String
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationUrl = "verification_url"
        case expiresIn = "expires_in"
        case interval
    }
}

struct TraktToken: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let createdAt: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case createdAt = "created_at"
    }

    var expiryDate: Date {
        Date(timeIntervalSince1970: TimeInterval(createdAt + expiresIn))
    }
    var isExpired: Bool { Date() >= expiryDate }
}

struct TraktUser: Codable {
    let username: String?
    let name: String?
}

struct TraktSettingsResponse: Codable {
    let user: TraktUser?
}

/// An item in a Trakt list / watchlist / watched response. Trakt nests the
/// movie or show object under a key; we decode whichever is present.
struct TraktListItem: Codable {
    let type: String?
    let movie: TraktMedia?
    let show: TraktMedia?

    var media: TraktMedia? { movie ?? show }
    var contentType: ContentType { (movie != nil) ? .movie : .series }
}

struct TraktMedia: Codable {
    let title: String?
    let year: Int?
    let ids: TraktIDs?
}

struct TraktIDs: Codable {
    let trakt: Int?
    let slug: String?
    let imdb: String?
    let tmdb: Int?
}

// MARK: - Trakt scrobble

struct TraktScrobbleResponse: Codable {
    let action: String?
    let progress: Double?
}

// MARK: - Cast & related (TMDB)

/// A single cast member for the detail screen's Cast rail.
struct CastMember: Identifiable, Hashable {
    let id: Int
    let name: String
    let character: String?
    let profileURL: URL?
}

struct TMDBCreditsResponse: Codable {
    let cast: [TMDBCastEntry]
}

struct TMDBCastEntry: Codable {
    let id: Int
    let name: String
    let character: String?
    let profilePath: String?
    enum CodingKeys: String, CodingKey {
        case id, name, character
        case profilePath = "profile_path"
    }
}

struct TMDBRelatedResponse: Codable {
    let results: [TMDBRelatedEntry]
}

/// A person's combined (movie + TV) filmography from TMDB.
struct TMDBPersonCreditsResponse: Codable {
    let cast: [TMDBPersonCredit]
}

struct TMDBPersonCredit: Codable {
    let id: Int
    let title: String?
    let name: String?
    let posterPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let mediaType: String?
    let popularity: Double?
    enum CodingKeys: String, CodingKey {
        case id, title, name, popularity
        case posterPath = "poster_path"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case mediaType = "media_type"
    }
}

struct TMDBRelatedEntry: Codable {
    let id: Int
    let title: String?
    let name: String?
    let posterPath: String?
    let backdropPath: String?
    let firstAirDate: String?
    let releaseDate: String?
    enum CodingKeys: String, CodingKey {
        case id, title, name
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case firstAirDate = "first_air_date"
        case releaseDate = "release_date"
    }
}
