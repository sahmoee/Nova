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

    /// Like `search`, but resolves up to `limit` titles — used by the shelf and
    /// playlist builders, which may want a specific count (e.g. a 5-movie lineup).
    func resolveTitles(for prompt: String, limit: Int = 20) async throws -> [CatalogItem] {
        guard let url = Self.workerURL else { throw AISearchError.notConfigured }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["query": prompt])
        req.timeoutInterval = 30

        let titles: [String]
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw AISearchError.requestFailed
            }
            titles = try JSONDecoder().decode(AIWorkerResponse.self, from: data).titles
        } catch let e as AISearchError {
            throw e
        } catch {
            throw AISearchError.requestFailed
        }
        guard !titles.isEmpty else { throw AISearchError.emptyResponse }

        var results: [CatalogItem] = []
        var seen = Set<String>()
        for title in titles.prefix(limit) {
            if let matches = try? await tmdb.search(title), let first = matches.first {
                if seen.insert(first.id).inserted { results.append(first) }
            }
        }
        return results
    }

    /// Natural-language search over the user's own library. Asks the Worker to turn the
    /// description into candidate titles, then fuzzy-matches them against library items
    /// by title. Falls back to a local keyword match if the Worker isn't configured, so
    /// vague library search still does something useful offline.
    func searchLibrary(_ query: String, in items: [MediaItem]) async -> [MediaItem] {
        // Try the Worker first for "vibe"/description queries.
        if Self.isConfigured, let url = Self.workerURL {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let body = try? JSONEncoder().encode(["query": query]) {
                req.httpBody = body
                req.timeoutInterval = 30
                if let (data, response) = try? await session.data(for: req),
                   let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                   let decoded = try? JSONDecoder().decode(AIWorkerResponse.self, from: data) {
                    let matched = matchTitles(decoded.titles, against: items)
                    if !matched.isEmpty { return matched }
                }
            }
        }
        // Fallback: local keyword match against title/series.
        return localKeywordMatch(query, in: items)
    }

    /// Matches AI-suggested title strings against library items (case-insensitive
    /// substring, either direction).
    private func matchTitles(_ titles: [String], against items: [MediaItem]) -> [MediaItem] {
        var out: [MediaItem] = []
        var seen = Set<UUID>()
        for title in titles {
            let needle = title.lowercased()
            for item in items {
                let hay = (item.seriesTitle ?? item.title).lowercased()
                if (hay.contains(needle) || needle.contains(hay)), seen.insert(item.id).inserted {
                    out.append(item)
                }
            }
        }
        return out
    }

    /// A simple offline keyword match used when the Worker isn't available.
    private func localKeywordMatch(_ query: String, in items: [MediaItem]) -> [MediaItem] {
        let words = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
        guard !words.isEmpty else { return [] }
        return items.filter { item in
            let hay = (item.seriesTitle ?? item.title).lowercased()
            return words.contains { hay.contains($0) }
        }
    }

    // MARK: - AI capabilities

    /// The distinct things AI can do in the app. Each maps a user prompt to a
    /// specialized instruction so the same Worker returns purpose-built results.
    enum Capability: String, CaseIterable, Identifiable {
        case discover        = "Discover"
        case librarySearch   = "Library Search"
        case buildCollection = "Build Collection"
        case buildLineup     = "Movie Night"
        case similarTo       = "More Like This"
        case moodMatch       = "By Mood"
        case franchiseOrder  = "Watch Order"
        case hiddenGems      = "Hidden Gems"
        case familyFriendly  = "Family Picks"
        case quickWatch      = "Short on Time"
        case surpriseMe      = "Surprise Me"
        case fillGaps        = "Fill My Gaps"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .discover:        return "sparkles"
            case .librarySearch:   return "magnifyingglass"
            case .buildCollection: return "rectangle.stack.badge.plus"
            case .buildLineup:     return "popcorn"
            case .similarTo:       return "square.on.square"
            case .moodMatch:       return "theatermasks"
            case .franchiseOrder:  return "list.number"
            case .hiddenGems:      return "diamond"
            case .familyFriendly:  return "figure.2.and.child.holdinghands"
            case .quickWatch:      return "timer"
            case .surpriseMe:      return "dice"
            case .fillGaps:        return "puzzlepiece.extension"
            }
        }

        /// A short prompt hint shown in the field.
        var placeholder: String {
            switch self {
            case .discover:        return "e.g. dark sci-fi thrillers"
            case .librarySearch:   return "e.g. something funny but not stupid"
            case .buildCollection: return "e.g. best heist movies"
            case .buildLineup:     return "e.g. cozy Friday night, 3 films"
            case .similarTo:       return "e.g. more like Inception"
            case .moodMatch:       return "e.g. I feel nostalgic"
            case .franchiseOrder:  return "e.g. the MCU in story order"
            case .hiddenGems:      return "e.g. underrated 2010s sci-fi"
            case .familyFriendly:  return "e.g. fun for a 7 year old"
            case .quickWatch:      return "e.g. under 100 minutes tonight"
            case .surpriseMe:      return "anything — tap Go"
            case .fillGaps:        return "e.g. classics I should have seen"
            }
        }

        /// Whether this capability searches the user's own library (versus the
        /// wider catalog).
        var searchesLibrary: Bool { self == .librarySearch }

        /// Whether the results can be saved as a new collection.
        var producesCollection: Bool {
            switch self {
            case .buildCollection, .buildLineup, .similarTo, .moodMatch,
                 .franchiseOrder, .hiddenGems, .familyFriendly, .quickWatch,
                 .surpriseMe, .fillGaps:
                return true
            case .discover, .librarySearch:
                return false
            }
        }

        /// Turns the user's words into a specialized instruction for the Worker.
        func instruction(for userText: String) -> String {
            let text = userText.trimmingCharacters(in: .whitespacesAndNewlines)
            switch self {
            case .discover:
                return text
            case .librarySearch:
                return text
            case .buildCollection:
                return "Build a themed collection of movies and shows for: \(text). Return a cohesive set of titles."
            case .buildLineup:
                return "Plan a movie-night lineup for: \(text). Order the titles so they flow well back to back."
            case .similarTo:
                return "List titles that are similar in tone, theme, and style to: \(text)."
            case .moodMatch:
                return "Recommend titles that fit this mood or feeling: \(text)."
            case .franchiseOrder:
                return "List the titles for \(text) in the ideal watch order. Return them in order."
            case .hiddenGems:
                return "Suggest lesser-known, underrated, high-quality titles for: \(text)."
            case .familyFriendly:
                return "Suggest age-appropriate, family-friendly titles for: \(text)."
            case .quickWatch:
                return "Suggest shorter titles that fit a limited time for: \(text)."
            case .surpriseMe:
                let seed = text.isEmpty ? "a great, well-reviewed mix across genres" : text
                return "Surprise me with an eclectic, high-quality set of titles: \(seed)."
            case .fillGaps:
                return "Suggest well-regarded essential titles someone may have missed for: \(text)."
            }
        }
    }

    /// Runs a capability: builds the specialized instruction and resolves catalog
    /// titles. Library-search capabilities are handled separately by the view.
    func run(_ capability: Capability, userText: String, limit: Int = 24) async throws -> [CatalogItem] {
        try await resolveTitles(for: capability.instruction(for: userText), limit: limit)
    }
}

private struct AIWorkerResponse: Codable {
    let titles: [String]

}
