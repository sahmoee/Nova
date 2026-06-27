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

    init(session: URLSession = .shared,
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

        var req = URLRequest(url: comps.url!)
        req.timeoutInterval = 25

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
