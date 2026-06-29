//
//  TMDBClient.swift
//  FrameTV
//
//  The Movie Database client. Provides search, detailed metadata, artwork, and
//  IMDB id resolution (which Stremio addons need). Uses a v3 API key from
//  AppConfig (Settings or config file). Degrades gracefully when no key is set.
//

import Foundation

enum TMDBError: LocalizedError {
    case missingKey
    case network(Error)
    case http(Int)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .missingKey:    return "No TMDB API key set. Add one in Settings to enable metadata."
        case .network(let e):return "Network error contacting TMDB: \(e.localizedDescription)"
        case .http(let c):   return "TMDB request failed (HTTP \(c))."
        case .decoding:      return "Couldn't read the TMDB response."
        }
    }
}

actor TMDBClient {

    private static let base = URL(string: "https://api.themoviedb.org/3")!
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let keyProvider: @Sendable () -> String?

    init(session: URLSession = AppNetworking.shared,
         keyProvider: @escaping @Sendable () -> String? = { AppConfig.shared.tmdbKey }) {
        self.session = session
        self.keyProvider = keyProvider
    }

    var hasKey: Bool { (keyProvider()?.isEmpty == false) }

    // MARK: - Search

    func searchMovies(_ query: String) async throws -> [CatalogItem] {
        let resp: TMDBSearchResponse<TMDBMovie> = try await get(
            "search/movie", query: ["query": query]
        )
        return resp.results.map { movie in
            CatalogItem(
                contentID: ContentID(tmdb: movie.id, type: .movie),
                title: movie.title ?? "Untitled",
                overview: movie.overview,
                posterURL: TMDBImage.poster(movie.posterPath),
                backdropURL: TMDBImage.backdrop(movie.backdropPath),
                year: movie.year,
                rating: movie.voteAverage
            )
        }
    }

    func searchShows(_ query: String) async throws -> [CatalogItem] {
        let resp: TMDBSearchResponse<TMDBShow> = try await get(
            "search/tv", query: ["query": query]
        )
        return resp.results.map { show in
            CatalogItem(
                contentID: ContentID(tmdb: show.id, type: .series),
                title: show.name ?? "Untitled",
                overview: show.overview,
                posterURL: TMDBImage.poster(show.posterPath),
                backdropURL: TMDBImage.backdrop(show.backdropPath),
                year: show.year,
                rating: show.voteAverage
            )
        }
    }

    /// Multi-search returning both movies and shows.
    func search(_ query: String) async throws -> [CatalogItem] {
        async let movies = try? searchMovies(query)
        async let shows = try? searchShows(query)
        let m = (await movies) ?? []
        let s = (await shows) ?? []
        // Interleave, movies and shows, preserving rough relevance.
        return m + s
    }

    // MARK: - Discovery catalogs (home shelves)

    private func mapMovies(_ results: [TMDBMovie]) -> [CatalogItem] {
        results.map {
            CatalogItem(contentID: ContentID(tmdb: $0.id, type: .movie),
                        title: $0.title ?? "Untitled", overview: $0.overview,
                        posterURL: TMDBImage.poster($0.posterPath),
                        backdropURL: TMDBImage.backdrop($0.backdropPath),
                        year: $0.year, rating: $0.voteAverage)
        }
    }
    private func mapShows(_ results: [TMDBShow]) -> [CatalogItem] {
        results.map {
            CatalogItem(contentID: ContentID(tmdb: $0.id, type: .series),
                        title: $0.name ?? "Untitled", overview: $0.overview,
                        posterURL: TMDBImage.poster($0.posterPath),
                        backdropURL: TMDBImage.backdrop($0.backdropPath),
                        year: $0.year, rating: $0.voteAverage)
        }
    }

    func trendingMovies() async throws -> [CatalogItem] {
        let resp: TMDBSearchResponse<TMDBMovie> = try await get("trending/movie/week")
        return mapMovies(resp.results)
    }
    func trendingShows() async throws -> [CatalogItem] {
        let resp: TMDBSearchResponse<TMDBShow> = try await get("trending/tv/week")
        return mapShows(resp.results)
    }
    func popularMovies() async throws -> [CatalogItem] {
        let resp: TMDBSearchResponse<TMDBMovie> = try await get("movie/popular")
        return mapMovies(resp.results)
    }
    func nowPlayingMovies() async throws -> [CatalogItem] {
        let resp: TMDBSearchResponse<TMDBMovie> = try await get("movie/now_playing")
        return mapMovies(resp.results)
    }
    func topRatedMovies() async throws -> [CatalogItem] {
        let resp: TMDBSearchResponse<TMDBMovie> = try await get("movie/top_rated")
        return mapMovies(resp.results)
    }
    func popularShows() async throws -> [CatalogItem] {
        let resp: TMDBSearchResponse<TMDBShow> = try await get("tv/popular")
        return mapShows(resp.results)
    }
    func airingTodayShows() async throws -> [CatalogItem] {
        let resp: TMDBSearchResponse<TMDBShow> = try await get("tv/airing_today")
        return mapShows(resp.results)
    }

    // MARK: - Details + IMDB resolution

    /// Fetches a movie's external ids (to get its IMDB id for addon stream lookups).
    func movieIMDBID(tmdbID: Int) async throws -> String? {
        let ext: TMDBExternalIDs = try await get("movie/\(tmdbID)/external_ids")
        return ext.imdbId
    }

    func showIMDBID(tmdbID: Int) async throws -> String? {
        let ext: TMDBExternalIDs = try await get("tv/\(tmdbID)/external_ids")
        return ext.imdbId
    }

    /// Fetches the poster and backdrop URLs for a TMDB id. Trakt only returns ids and
    /// titles, so we use this to fill in artwork for watchlist/Trakt rows.
    func artwork(tmdbID: Int, isMovie: Bool) async throws -> (poster: URL?, backdrop: URL?) {
        let path = isMovie ? "movie/\(tmdbID)" : "tv/\(tmdbID)"
        let detail: TMDBArtworkDetail = try await get(path)
        return (TMDBImage.poster(detail.posterPath), TMDBImage.backdrop(detail.backdropPath))
    }

    /// Returns a YouTube URL for the best trailer for a TMDB id, or nil if none.
    /// Prefers an official "Trailer" of type YouTube; falls back to any YouTube
    /// teaser/clip. Used by the detail screen's Play Trailer button.
    func trailerURL(tmdbID: Int, isMovie: Bool) async throws -> URL? {
        let path = isMovie ? "movie/\(tmdbID)/videos" : "tv/\(tmdbID)/videos"
        let response: TMDBVideosResponse = try await get(path)
        let youtube = response.results.filter { $0.site.lowercased() == "youtube" }
        // Prefer an official trailer, then any trailer, then any teaser/clip.
        let best = youtube.first(where: { $0.type == "Trailer" && $0.official })
            ?? youtube.first(where: { $0.type == "Trailer" })
            ?? youtube.first(where: { $0.type == "Teaser" })
            ?? youtube.first
        guard let key = best?.key else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(key)")
    }

    /// Enriches a list of CatalogItems (e.g. from Trakt) that have TMDB ids but no
    /// artwork. Runs lookups concurrently and leaves items without a TMDB id untouched.
    func enrichArtwork(_ items: [CatalogItem]) async -> [CatalogItem] {
        guard hasKey else { return items }
        return await withTaskGroup(of: (Int, URL?, URL?).self) { group -> [CatalogItem] in
            for (idx, item) in items.enumerated() {
                // Only look up items that need artwork and have a TMDB id.
                guard item.posterURL == nil, let tmdb = item.contentID.tmdb else { continue }
                let isMovie = item.contentID.type == .movie
                group.addTask {
                    let art = try? await self.artwork(tmdbID: tmdb, isMovie: isMovie)
                    return (idx, art?.poster, art?.backdrop)
                }
            }
            var result = items
            for await (idx, poster, backdrop) in group {
                if result.indices.contains(idx) {
                    if result[idx].posterURL == nil { result[idx].posterURL = poster }
                    if result[idx].backdropURL == nil { result[idx].backdropURL = backdrop }
                }
            }
            return result
        }
    }

    /// Fully hydrates a series CatalogItem with seasons and episodes plus its IMDB id.
    func hydrateSeries(_ item: CatalogItem) async throws -> CatalogItem {
        guard let tmdb = item.contentID.tmdb else { return item }
        var result = item

        // External ids (IMDB).
        if result.contentID.imdb == nil {
            result.contentID.imdb = try? await showIMDBID(tmdbID: tmdb)
        }

        // Show detail for season list.
        let show: TMDBShow = try await get("tv/\(tmdb)")
        let seasonNumbers = (show.seasons ?? [])
            .compactMap { $0.seasonNumber }
            .filter { $0 >= 0 }
            .sorted()

        var seasons: [SeasonInfo] = []
        // Fetch each season's episodes concurrently.
        await withTaskGroup(of: SeasonInfo?.self) { group in
            for num in seasonNumbers {
                group.addTask { [self] in
                    guard let detail: TMDBSeasonDetail = try? await get("tv/\(tmdb)/season/\(num)") else {
                        return nil
                    }
                    let episodes = (detail.episodes ?? []).map { ep in
                        EpisodeInfo(
                            season: ep.seasonNumber ?? num,
                            number: ep.episodeNumber ?? 0,
                            title: ep.name,
                            overview: ep.overview,
                            stillURL: TMDBImage.still(ep.stillPath),
                            airDate: parseDate(ep.airDate),
                            runtime: ep.runtime.map { TimeInterval($0 * 60) }
                        )
                    }
                    return SeasonInfo(number: num, name: detail.name, episodes: episodes)
                }
            }
            for await season in group {
                if let season { seasons.append(season) }
            }
        }

        result.seasons = seasons.sorted { $0.number < $1.number }
        return result
    }

    /// Hydrates a movie with its IMDB id (for addon lookups).
    func hydrateMovie(_ item: CatalogItem) async throws -> CatalogItem {
        guard let tmdb = item.contentID.tmdb, item.contentID.imdb == nil else { return item }
        var result = item
        result.contentID.imdb = try? await movieIMDBID(tmdbID: tmdb)
        return result
    }

    // MARK: - Networking

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        guard let key = keyProvider(), !key.isEmpty else { throw TMDBError.missingKey }

        var comps = URLComponents(url: Self.base.appendingPathComponent(path),
                                  resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "api_key", value: key),
                     URLQueryItem(name: "language", value: "en-US")]
        for (k, v) in query { items.append(URLQueryItem(name: k, value: v)) }
        comps.queryItems = items

        // Build the request immutably so it can be safely captured by the retry
        // closure (a mutable var capture is an error in the Swift 6 language mode).
        let req: URLRequest = {
            var r = URLRequest(url: comps.url!)
            r.timeoutInterval = 25
            return r
        }()

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await withRetry {
                try await self.session.data(for: req)
            }
        } catch {
            FrameLog.network.error("TMDB request failed: \(error.localizedDescription, privacy: .public)")
            throw TMDBError.network(error)
        }
        guard let http = response as? HTTPURLResponse else { throw TMDBError.http(-1) }
        guard (200...299).contains(http.statusCode) else { throw TMDBError.http(http.statusCode) }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw TMDBError.decoding(error)
        }
    }

    private nonisolated func parseDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: s)
    }
}
