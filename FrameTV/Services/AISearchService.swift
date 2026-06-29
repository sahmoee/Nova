//
//  AISearchService.swift
//  FrameTV
//
//  Natural-language search/suggestions powered by Claude. For security, FrameTV does
//  NOT hold an Anthropic API key. Instead it calls a small Cloudflare Worker that the
//  user deploys themselves; the Worker holds the API key server-side and returns a
//  list of title suggestions. The Worker URL is configured by the user in Settings.
//
//  Expected Worker contract:
//    POST <workerURL>
//    Body:    { "query": "<the user's natural language request>" }
//    Returns: { "titles": ["The Matrix", "Inception", ...] }   // plain title strings
//
//  The app then resolves those titles to real catalog items via TMDB, so nothing
//  about the user's library or keys is exposed to the model.
//

import Foundation

enum AISearchError: LocalizedError {
    case notConfigured
    case requestFailed
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "AI search isn't set up yet. Add your Cloudflare Worker URL in Settings ▸ AI Search."
        case .requestFailed: return "The AI search request failed. Check your Worker URL and that it's deployed."
        case .emptyResponse: return "The AI didn't return any suggestions for that."
        }
    }
}

@MainActor
final class AISearchService: ObservableObject {

    /// The user-configured Worker endpoint. Stored as a plain URL (not a secret) and
    /// synced across devices via iCloud key-value storage.
    static let workerURLKey = "ai.workerURL"

    static var workerURLString: String {
        get {
            // iCloud value wins, then local, then config file.
            if let cloud = CloudSync.shared.string(forKey: workerURLKey),
               !cloud.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return cloud
            }
            return UserDefaults.standard.string(forKey: workerURLKey) ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: workerURLKey)
            CloudSync.shared.setString(newValue, forKey: workerURLKey)
            CloudSync.shared.flush()
        }
    }

    static var workerURL: URL? {
        let trimmed = workerURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return AppConfig.shared.aiWorkerURL.flatMap(URL.init(string:))
        }
        return URL(string: trimmed)
    }

    static var isConfigured: Bool { !SafeMode.isOn && workerURL != nil }

    private let tmdb: TMDBClient
    private let session = AppNetworking.shared

    init(tmdb: TMDBClient) {
        self.tmdb = tmdb
    }

    /// Sends a natural-language query to the Worker, gets back title strings, and
    /// resolves them to catalog items via TMDB.
    func search(_ query: String) async throws -> [CatalogItem] {
        guard let url = Self.workerURL else { throw AISearchError.notConfigured }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["query": query])
        req.timeoutInterval = 30

        let titles: [String]
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw AISearchError.requestFailed
            }
            let decoded = try JSONDecoder().decode(AIWorkerResponse.self, from: data)
            titles = decoded.titles
        } catch let e as AISearchError {
            throw e
        } catch {
            throw AISearchError.requestFailed
        }

        guard !titles.isEmpty else { throw AISearchError.emptyResponse }

        // Resolve each suggested title to a real catalog item (first TMDB match).
        var results: [CatalogItem] = []
        var seen = Set<String>()
        for title in titles.prefix(20) {
            if let matches = try? await tmdb.search(title), let first = matches.first {
                if seen.insert(first.id).inserted { results.append(first) }
            }
        }
        return results
    }
}

private struct AIWorkerResponse: Codable {
    let titles: [String]
}
