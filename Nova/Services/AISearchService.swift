//
//  AISearchService.swift
//  Nova
//
//  Natural-language search/suggestions powered by Claude. For security, Nova does
//  NOT hold an Anthropic API key. Instead it calls a small Cloudflare Worker that the
//  user deploys themselves; the Worker holds the API key server-side and returns a
//  list of title suggestions. The Worker URL is configured by the user in Settings.
//
//  Expected Worker contract:
//    POST <workerURL>/titles
//    Body:    { "query": "<the user's natural language request>" }
//    Returns: { "titles": ["The Matrix", "Inception", ...] }   // plain title strings
//
//  Multi-collection requests add mode/count and receive an additive `collections`
//  field while retaining the flattened `titles` array for released clients.
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

    struct CollectionSuggestion: Identifiable {
        let id = UUID()
        let name: String
        let items: [CatalogItem]
    }

    /// The user-configured Worker endpoint. Stored as a plain URL (not a secret) and
    /// synced across devices via iCloud key-value storage.
    static let workerURLKey = PrefKey.aiWorkerURL

    static var workerURLString: String {
        get {
            // iCloud value wins, then local, then config file.
            if let cloud = CloudSync.shared.string(forKey: workerURLKey),
               !cloud.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return cloud
            }
            return UserDefaults.standard.string(forKey: workerURLKey)
                ?? AppConfig.shared.aiWorkerURL
                ?? NovaWorkerConfiguration.defaultBaseURL
        }
        set {
            UserDefaults.standard.set(newValue, forKey: workerURLKey)
            CloudSync.shared.setString(newValue, forKey: workerURLKey)
            CloudSync.shared.flush()
        }
    }

    static var workerURL: URL? {
        let trimmed = workerURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return URL(string: NovaWorkerConfiguration.defaultBaseURL) }
        return URL(string: trimmed)
    }

    static var isConfigured: Bool { !SafeMode.isOn && workerURL != nil }

    /// Bearer auth header for Worker calls, if a Worker token is configured. The
    /// Worker enforces it only when its NOVA_SHARED_TOKEN secret is set.
    static var authHeaders: [String: String] {
        guard let token = AppConfig.shared.workerToken, !token.isEmpty else { return [:] }
        return ["Authorization": "Bearer \(token)"]
    }

    private let tmdb: TMDBClient

    init(tmdb: TMDBClient) {
        self.tmdb = tmdb
    }

    // MARK: - Worker fetch + TMDB resolution (shared plumbing)

    /// Sends a query to the Worker and returns raw title strings. The single place
    /// the Worker is called — search, shelf building, and library search all route
    /// through here.
    private func fetchTitles(_ query: String) async throws -> [String] {
        guard let base = Self.workerURL else { throw AISearchError.notConfigured }
        let url = NovaWorkerConfiguration.endpoint(base: base, path: NovaIdentifiers.WorkerPath.titles)
        let decoded: AIWorkerResponse
        do {
            decoded = try await AppNetworking.postJSON(
                url,
                body: AIWorkerRequest(query: query, mode: nil, count: nil),
                headers: Self.authHeaders
            )
        } catch {
            NovaLog.network.error("AI Worker request failed: \(error.localizedDescription, privacy: .public)")
            throw AISearchError.requestFailed
        }
        guard !decoded.titles.isEmpty else { throw AISearchError.emptyResponse }
        return decoded.titles
    }

    /// Resolves title strings to catalog items via TMDB — in parallel, preserving
    /// the Worker's order (it is often meaningful, e.g. watch order), deduplicated
    /// by catalog id. Failures are logged instead of silently swallowed.
    private func resolve(_ titles: [String], limit: Int) async -> [CatalogItem] {
        let wanted = Array(titles.prefix(limit))
        let resolved: [(Int, CatalogItem)] = await withTaskGroup(of: (Int, CatalogItem?).self) { group in
            for (idx, title) in wanted.enumerated() {
                group.addTask { [tmdb] in
                    do {
                        return (idx, try await tmdb.search(title).first)
                    } catch {
                        NovaLog.catalog.error("TMDB resolve failed for AI title: \(error.localizedDescription, privacy: .public)")
                        return (idx, nil)
                    }
                }
            }
            var out: [(Int, CatalogItem)] = []
            for await (idx, item) in group {
                if let item { out.append((idx, item)) }
            }
            return out
        }
        var results: [CatalogItem] = []
        var seen = Set<String>()
        for (_, item) in resolved.sorted(by: { $0.0 < $1.0 }) {
            if seen.insert(item.id).inserted { results.append(item) }
        }
        return results
    }

    /// Sends a natural-language query to the Worker, gets back title strings, and
    /// resolves them to catalog items via TMDB.
    func search(_ query: String) async throws -> [CatalogItem] {
        let titles = try await fetchTitles(query)
        return await resolve(titles, limit: 20)
    }

    /// Like `search`, but resolves up to `limit` titles — used by the shelf and
    /// playlist builders, which may want a specific count (e.g. a 5-movie lineup).
    func resolveTitles(for prompt: String, limit: Int = 20) async throws -> [CatalogItem] {
        let titles = try await fetchTitles(prompt)
        return await resolve(titles, limit: limit)
    }

    /// Builds several named collection previews in one request. The Worker keeps
    /// the legacy flattened `titles` field, making the contract additive.
    func buildCollections(for prompt: String, count: Int) async throws -> [CollectionSuggestion] {
        guard let base = Self.workerURL else { throw AISearchError.notConfigured }
        let url = NovaWorkerConfiguration.endpoint(base: base, path: NovaIdentifiers.WorkerPath.titles)
        let requested = min(max(count, 2), 8)
        let decoded: AIWorkerResponse
        do {
            decoded = try await AppNetworking.postJSON(
                url,
                body: AIWorkerRequest(query: prompt, mode: "collections", count: requested),
                headers: Self.authHeaders
            )
        } catch {
            NovaLog.network.error("AI collection request failed: \(error.localizedDescription, privacy: .public)")
            throw AISearchError.requestFailed
        }
        guard let groups = decoded.collections, !groups.isEmpty else {
            throw AISearchError.emptyResponse
        }
        var suggestions: [CollectionSuggestion] = []
        for group in groups.prefix(requested) {
            let items = await resolve(group.titles, limit: 20)
            if !items.isEmpty {
                suggestions.append(CollectionSuggestion(name: group.name, items: items))
            }
        }
        guard !suggestions.isEmpty else { throw AISearchError.emptyResponse }
        return suggestions
    }

    static func requestedCollectionCount(in prompt: String) -> Int {
        let pattern = #"(?i)\b(?:build|create|make)?\s*(\d{1,2})\s+collections?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: prompt, range: NSRange(prompt.startIndex..., in: prompt)),
              let range = Range(match.range(at: 1), in: prompt),
              let count = Int(prompt[range]) else { return 1 }
        return min(max(count, 1), 8)
    }

    /// Natural-language search over the user's own library. Asks the Worker to turn the
    /// description into candidate titles, then fuzzy-matches them against library items
    /// by title. Falls back to a local keyword match if the Worker isn't configured, so
    /// vague library search still does something useful offline.
    func searchLibrary(_ query: String, in items: [MediaItem]) async -> [MediaItem] {
        // Try the Worker first for "vibe"/description queries.
        if Self.isConfigured {
            if let titles = try? await fetchTitles(query) {
                let matched = matchTitles(titles, against: items)
                if !matched.isEmpty { return matched }
            }
        }
        // Fallback: local keyword match against title/series.
        return localKeywordMatch(query, in: items)
    }

    /// Matches AI-suggested title strings against library items (case-insensitive
    /// substring, either direction).
    private func matchTitles(_ titles: [String], against items: [MediaItem]) -> [MediaItem] {
        // Lowercase every haystack once up front instead of per title x item.
        let haystacks = items.map { ($0, ($0.seriesTitle ?? $0.title).lowercased()) }
        var out: [MediaItem] = []
        var seen = Set<UUID>()
        for title in titles {
            let needle = title.lowercased()
            for (item, hay) in haystacks {
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
        case buildShelf      = "Build a Shelf"
        case doubleFeature   = "Double Feature"
        case bingeQueue      = "Binge Queue"
        case decade          = "By Decade"
        case director        = "By Director or Cast"
        case criticPicks     = "Critically Acclaimed"
        case genreBlend      = "Genre Blend"
        case foreign         = "Foreign & World"
        case comfortWatch    = "Comfort Watch"
        case soundtrack      = "Great Soundtracks"
        case basedOnBooks    = "Based on Books"

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
            case .buildShelf:      return "rectangle.grid.1x2"
            case .doubleFeature:   return "film.stack"
            case .bingeQueue:      return "rectangle.stack.badge.play"
            case .decade:          return "calendar"
            case .director:        return "person.crop.rectangle"
            case .criticPicks:     return "rosette"
            case .genreBlend:      return "wand.and.rays"
            case .foreign:         return "globe"
            case .comfortWatch:    return "cup.and.saucer"
            case .soundtrack:      return "music.note.list"
            case .basedOnBooks:    return "book"
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
            case .buildShelf:      return "e.g. neo-noir crime, save as a shelf"
            case .doubleFeature:   return "e.g. a horror double bill"
            case .bingeQueue:      return "e.g. bingeable sci-fi series"
            case .decade:          return "e.g. the best of the 90s"
            case .director:        return "e.g. Denis Villeneuve films"
            case .criticPicks:     return "e.g. award-winning dramas"
            case .genreBlend:      return "e.g. romantic comedies with sci-fi"
            case .foreign:         return "e.g. Korean thrillers"
            case .comfortWatch:    return "e.g. cozy rewatchable shows"
            case .soundtrack:      return "e.g. films with iconic scores"
            case .basedOnBooks:    return "e.g. great book-to-film adaptations"
            }
        }

        // MARK: Feature menu metadata

        /// Groups used to present the AI features as an organized, browsable menu.
        enum Category: String, CaseIterable, Identifiable {
            case build     = "Build & Organize"
            case discover  = "Discover Something New"
            case taste     = "By Taste & Mood"
            case practical = "Practical Picks"

            var id: String { rawValue }

            var systemImage: String {
                switch self {
                case .build:     return "rectangle.stack.badge.plus"
                case .discover:  return "sparkles"
                case .taste:     return "theatermasks"
                case .practical: return "checklist"
                }
            }
        }

        /// Which menu group this capability belongs to.
        var category: Category {
            switch self {
            case .buildShelf, .buildCollection, .buildLineup, .bingeQueue,
                 .doubleFeature, .franchiseOrder:
                return .build
            case .discover, .surpriseMe, .hiddenGems, .fillGaps, .foreign,
                 .criticPicks, .basedOnBooks, .soundtrack:
                return .discover
            case .similarTo, .moodMatch, .genreBlend, .decade, .director,
                 .comfortWatch:
                return .taste
            case .librarySearch, .familyFriendly, .quickWatch:
                return .practical
            }
        }

        /// One-line description shown on the feature's card in the AI menu.
        var blurb: String {
            switch self {
            case .discover:        return "Describe a vibe and get real titles."
            case .librarySearch:   return "Find things you own by fuzzy memory."
            case .buildCollection: return "Create a themed collection in one tap."
            case .buildLineup:     return "Plan a movie night that flows."
            case .similarTo:       return "More titles like one you love."
            case .moodMatch:       return "Tell it how you feel; it picks."
            case .franchiseOrder:  return "Any saga in the ideal watch order."
            case .hiddenGems:      return "Underrated titles worth your time."
            case .familyFriendly:  return "Safe picks for any age."
            case .quickWatch:      return "Great picks when time is short."
            case .surpriseMe:      return "Zero effort. Tap and go."
            case .fillGaps:        return "Essentials you have missed."
            case .buildShelf:      return "Generate a living shelf for Home."
            case .doubleFeature:   return "Two titles that pair perfectly."
            case .bingeQueue:      return "Series you will not want to stop."
            case .decade:          return "The best of any era."
            case .director:        return "Explore a filmmaker or star."
            case .criticPicks:     return "Award winners and acclaim."
            case .genreBlend:      return "Mash two genres together."
            case .foreign:         return "Standouts from world cinema."
            case .comfortWatch:    return "Cozy, easy, rewatchable."
            case .soundtrack:      return "Films with unforgettable music."
            case .basedOnBooks:    return "Great page-to-screen adaptations."
            }
        }

        /// Whether this capability searches the user's own library (versus the
        /// wider catalog).
        var searchesLibrary: Bool { self == .librarySearch }

        /// Whether the results can be saved as a Home shelf.
        var producesShelf: Bool { self == .buildShelf }

        /// Whether the results can be saved as a new collection.
        var producesCollection: Bool {
            switch self {
            case .buildCollection, .buildLineup, .similarTo, .moodMatch,
                 .franchiseOrder, .hiddenGems, .familyFriendly, .quickWatch,
                 .surpriseMe, .fillGaps, .buildShelf, .doubleFeature, .bingeQueue,
                 .decade, .director, .criticPicks, .genreBlend, .foreign,
                 .comfortWatch, .soundtrack, .basedOnBooks:
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
            case .buildShelf:
                return "Build a themed shelf of movies and shows for: \(text). Return a cohesive, well-rounded set."
            case .doubleFeature:
                return "Pick a double feature (two titles) that pair perfectly for: \(text). Return exactly two."
            case .bingeQueue:
                return "Build a binge queue of highly bingeable series for: \(text). Order them best first."
            case .decade:
                return "List the standout titles from the era or decade described: \(text)."
            case .director:
                return "List notable titles by the director, creator, or cast member described: \(text)."
            case .criticPicks:
                return "List critically acclaimed, award-recognized titles for: \(text)."
            case .genreBlend:
                return "List titles that blend the genres described: \(text)."
            case .foreign:
                return "List great non-English or world-cinema titles for: \(text)."
            case .comfortWatch:
                return "List cozy, easy, rewatchable comfort titles for: \(text)."
            case .soundtrack:
                return "List titles famous for their music or score for: \(text)."
            case .basedOnBooks:
                return "List well-regarded titles adapted from books for: \(text)."
            }
        }
    }

    /// Runs a capability: builds the specialized instruction and resolves catalog
    /// titles. Library-search capabilities are handled separately by the view.
    func run(_ capability: Capability, userText: String, limit: Int = 24) async throws -> [CatalogItem] {
        try await resolveTitles(for: capability.instruction(for: userText), limit: limit)
    }
}

private struct AIWorkerRequest: Codable {
    let query: String
    let mode: String?
    let count: Int?
}

private struct AIWorkerCollectionResponse: Codable {
    let name: String
    let titles: [String]
}

private struct AIWorkerResponse: Codable {
    let titles: [String]
    let collections: [AIWorkerCollectionResponse]?
}
