//
//  OMDbClient.swift
//  FrameTV
//
//  Fetches aggregate ratings (IMDb, Rotten Tomatoes, Metacritic) for a title from the
//  OMDb API, keyed by IMDb id. OMDb is a free, lightweight service that consolidates the
//  three best-known scores into a single response, which is the practical way to surface
//  IMDb and Rotten Tomatoes numbers (neither offers a usable public API of its own).
//
//  A free OMDb key is set in Settings (Metadata & Accounts). With no key, ratings simply
//  don't appear and nothing else is affected.
//

import Foundation

/// Consolidated external ratings for a title.
struct ExternalRatings: Equatable, Sendable {
    /// IMDb rating on a 0...10 scale (e.g. 7.8).
    var imdb: Double?
    /// Rotten Tomatoes score as a percentage 0...100 (e.g. 92).
    var rottenTomatoes: Int?
    /// Metacritic score 0...100 (e.g. 74).
    var metacritic: Int?

    var isEmpty: Bool { imdb == nil && rottenTomatoes == nil && metacritic == nil }
}

enum OMDbError: Error { case missingKey, network(Error), http(Int), notFound }

/// Minimal OMDb client. Looks up a title by IMDb id and extracts the three scores.
/// An actor (like TMDBClient) so it's Sendable and safe to hold in the environment.
actor OMDbClient {
    private let session: URLSession
    private let keyProvider: @Sendable () -> String?
    private static let base = URL(string: "https://www.omdbapi.com/")!

    init(session: URLSession = AppNetworking.shared,
         keyProvider: @escaping @Sendable () -> String? = { AppConfig.shared.omdbKey }) {
        self.session = session
        self.keyProvider = keyProvider
    }

    nonisolated var hasKey: Bool { keyProvider()?.isEmpty == false }

    /// Fetches ratings for a title by its IMDb id (e.g. "tt0903747"). Returns empty
    /// ratings (never throws to the UI) on any failure so the detail screen degrades
    /// gracefully.
    func ratings(forIMDB imdb: String) async -> ExternalRatings {
        guard let key = keyProvider(), !key.isEmpty else { return ExternalRatings() }
        var comps = URLComponents(url: Self.base, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "apikey", value: key),
            URLQueryItem(name: "i", value: imdb),
            URLQueryItem(name: "tomatoes", value: "true")
        ]
        guard let url = comps.url else { return ExternalRatings() }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return ExternalRatings()
            }
            let decoded = try JSONDecoder().decode(OMDbResponse.self, from: data)
            return decoded.toExternalRatings()
        } catch {
            FrameLog.network.error("OMDb request failed: \(error.localizedDescription, privacy: .public)")
            return ExternalRatings()
        }
    }
}

// MARK: - Response model

private struct OMDbResponse: Decodable {
    let response: String?
    let imdbRating: String?
    let ratings: [Rating]?

    enum CodingKeys: String, CodingKey {
        case response = "Response"
        case imdbRating
        case ratings = "Ratings"
    }

    struct Rating: Decodable {
        let source: String
        let value: String
        enum CodingKeys: String, CodingKey {
            case source = "Source"
            case value = "Value"
        }
    }

    func toExternalRatings() -> ExternalRatings {
        var out = ExternalRatings()
        if let r = imdbRating, let v = Double(r), v > 0 { out.imdb = v }
        for rating in ratings ?? [] {
            switch rating.source {
            case "Rotten Tomatoes":
                // Value like "92%".
                let digits = rating.value.filter { $0.isNumber }
                if let pct = Int(digits) { out.rottenTomatoes = pct }
            case "Metacritic":
                // Value like "74/100".
                let n = rating.value.split(separator: "/").first.map(String.init) ?? ""
                if let m = Int(n.filter { $0.isNumber }) { out.metacritic = m }
            default:
                break
            }
        }
        return out
    }
}
