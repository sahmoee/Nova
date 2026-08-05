//
//  UniversalSearchView.swift
//  Nova
//
//  The app's shared search experience: a search field with predictive title
//  suggestions (TMDB), recent searches, typo-tolerant correction, and natural-
//  language AI search. Used by both Discover and Home so the two behave identically.
//
//  It is self-contained — it owns its query/results state and pushes CatalogItem
//  onto the surrounding NavigationStack via NavigationLink(value:), so the host only
//  needs a `.navigationDestination(for: CatalogItem.self)`.
//
//  Works on iOS, iPadOS and tvOS.
//

import SwiftUI

struct UniversalSearchView: View {
    /// Prompt shown in the empty field.
    var prompt: String = "Search movies and shows"
    /// Storage key for recent searches, so callers can share or separate history.
    var recentsKey: String = "search.recent.universal"

    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var settings: SettingsStore

    @State private var query = ""
    @State private var results: [CatalogItem] = []
    @State private var correctedQuery: String?
    @State private var suggestions: [CatalogItem] = []
    @State private var state: ViewState = .idle
    @State private var searchTask: Task<Void, Never>?
    @State private var suggestTask: Task<Void, Never>?
    @State private var aiSearching = false
    @State private var aiError: String?
    @FocusState private var searchFocused: Bool

    @AppStorage private var recentSearchesRaw: String

    init(prompt: String = "Search movies and shows",
         recentsKey: String = "search.recent.universal") {
        self.prompt = prompt
        self.recentsKey = recentsKey
        _recentSearchesRaw = AppStorage(wrappedValue: "", recentsKey)
    }

    enum ViewState: Equatable { case idle, searching, results, empty, noKey }

    private let columns = [GridItem(.adaptive(minimum: Theme.CardSize.posterWidth * 0.95),
                                    spacing: Theme.Spacing.md)]

    /// True while the user is actively searching (field has content or results show),
    /// so the host can hide its own content behind the search UI.
    var isActive: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty || state != .idle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            searchField
            suggestionsView

            switch state {
            case .idle:
                EmptyView()
            case .searching:
                skeletonGrid
            case .results:
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    if let corrected = correctedQuery {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkle.magnifyingglass")
                                .foregroundStyle(Theme.Colors.accent)
                            Text("Showing results for “\(corrected)”")
                                .font(.appFont(17))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                    resultsBody
                }
            case .empty:
                EmptyStateView(systemImage: "magnifyingglass",
                               title: "No results",
                               message: "Nothing matched “\(query)”. Try a different title.")
                    .frame(height: 320)
            case .noKey:
                EmptyStateView(
                    systemImage: "key",
                    title: "Add a TMDB key to search",
                    message: "Search needs a free TMDB API key. Add one in Settings ▸ Metadata & Accounts, or drop an NovaConfig.json next to the app."
                )
                .frame(height: 360)
            }
        }
        .alert("AI Search", isPresented: .constant(aiError != nil)) {
            Button("OK") { aiError = nil }
        } message: {
            Text(aiError ?? "")
        }
        .onAppear { if !env.tmdb.hasKey { /* still allow typing; noKey shown on search */ } }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.appFont(24))
                .foregroundStyle(Theme.Colors.textSecondary)
            TextField(prompt, text: $query)
                .textFieldStyle(.plain)
                .font(.appFont(24))
                .foregroundStyle(Theme.Colors.textPrimary)
                .focused($searchFocused)
                #if os(iOS)
                .autocorrectionDisabled(false)
                .textInputAutocapitalization(.words)
                #endif
                .onSubmit { triggerSearch() }
                .onChange(of: query) { _, _ in debounceSearch(); debounceSuggest() }
            if !query.isEmpty {
                Button {
                    query = ""; results = []; suggestions = []; state = .idle
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.appFont(22))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .novaIconStyle()
            }
            Button {
                Task { await runAISearch() }
            } label: {
                Image(systemName: "sparkles")
                    .font(.appFont(22))
                    .foregroundStyle(aiSearching ? Theme.Colors.textTertiary : Theme.Colors.accent)
            }
            .novaIconStyle()
            .disabled(aiSearching || query.trimmingCharacters(in: .whitespaces).count < 2)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    // MARK: - Suggestions

    private var recentSearches: [String] {
        recentSearchesRaw.split(separator: "\n").map(String.init)
    }

    private func rememberSearch(_ term: String) {
        let t = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 2 else { return }
        var list = recentSearches.filter { $0.lowercased() != t.lowercased() }
        list.insert(t, at: 0)
        recentSearchesRaw = list.prefix(8).joined(separator: "\n")
    }

    @ViewBuilder
    private var suggestionsView: some View {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        #if os(tvOS)
        let showRecent = q.count < 2 && !recentSearches.isEmpty
        #else
        let showRecent = searchFocused && q.count < 2 && !recentSearches.isEmpty
        #endif
        if showRecent {
            VStack(alignment: .leading, spacing: 0) {
                Text("Recent")
                    .font(.appFont(15, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.sm)
                ForEach(recentSearches, id: \.self) { term in
                    Button {
                        query = term; searchFocused = false; triggerSearch()
                    } label: {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(Theme.Colors.textTertiary)
                            Text(term).foregroundStyle(Theme.Colors.textPrimary)
                            Spacer()
                        }
                        .font(.appFont(19))
                        .padding(Theme.Spacing.md)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(NovaListRowStyle())
                }
                Button("Clear recent searches") { recentSearchesRaw = "" }
                    .font(.appFont(16))
                    .foregroundStyle(Theme.Colors.accent)
                    .padding(Theme.Spacing.md)
            }
            .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        } else if !suggestions.isEmpty && q.count >= 2 {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(suggestions.prefix(6)) { item in
                    Button {
                        query = item.title; searchFocused = false; triggerSearch()
                    } label: {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(Theme.Colors.textTertiary)
                            Text(item.title).foregroundStyle(Theme.Colors.textPrimary).lineLimit(1)
                            if let year = item.year {
                                Text(String(year)).foregroundStyle(Theme.Colors.textTertiary)
                            }
                            Spacer()
                        }
                        .font(.appFont(19))
                        .padding(Theme.Spacing.md)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(NovaListRowStyle())
                }
            }
            .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsBody: some View {
        switch settings.searchLayout {
        case .grid:  grid(results)
        case .rails: resultRails
        }
    }

    @ViewBuilder
    private var resultRails: some View {
        let movies = results.filter { $0.contentID.type == .movie }
        let shows  = results.filter { $0.contentID.type == .series }
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            if !movies.isEmpty { resultRail(title: "Movies", items: movies) }
            if !shows.isEmpty { resultRail(title: "TV Shows", items: shows) }
            let other = results.filter { $0.contentID.type != .movie && $0.contentID.type != .series }
            if !other.isEmpty { resultRail(title: "More Results", items: other) }
        }
    }

    private func resultRail(title: String, items: [CatalogItem]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Font.sectionTitle())
                .foregroundStyle(Theme.Colors.textPrimary)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Theme.Spacing.md) {
                    ForEach(items) { item in
                        NavigationLink(value: item) { posterCard(item) }
                            .buttonStyle(NovaListRowStyle())
                    }
                }
                .padding(.vertical, Theme.Spacing.xs)
            }
        }
    }

    private func grid(_ items: [CatalogItem]) -> some View {
        LazyVGrid(columns: columns, spacing: Theme.Spacing.lg) {
            ForEach(items) { item in
                NavigationLink(value: item) { posterCard(item) }
                    .buttonStyle(NovaListRowStyle())
            }
        }
        .onAppear { ImageLoader.shared.prefetch(items.compactMap(\.posterURL)) }
    }

    private var skeletonGrid: some View {
        let w = Theme.CardSize.posterWidth * 0.95
        return LazyVGrid(columns: columns, spacing: Theme.Spacing.lg) {
            ForEach(0..<8, id: \.self) { _ in
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(Theme.Colors.card)
                        .frame(width: w, height: w * 1.5)
                        .shimmering()
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Theme.Colors.card)
                        .frame(width: w * 0.7, height: 14)
                        .shimmering()
                }
            }
        }
    }

    private func posterCard(_ item: CatalogItem) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            PosterImage(url: item.posterURL,
                        width: Theme.CardSize.posterWidth * 0.95,
                        height: Theme.CardSize.posterWidth * 0.95 * 1.5)
            Text(item.title)
                .font(.appFont(19, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
            HStack(spacing: 6) {
                Image(systemName: item.contentID.type == .movie ? "film" : "tv")
                if let year = item.year { Text(String(year)) }
            }
            .font(.appFont(15))
            .foregroundStyle(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: Theme.CardSize.posterWidth * 0.95)
    }

    // MARK: - Logic

    private func debounceSuggest() {
        suggestTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { suggestions = []; return }
        suggestTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            let found = await env.catalog.search(q)
            guard !Task.isCancelled else { return }
            await MainActor.run { suggestions = found }
        }
    }

    private func debounceSearch() {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else {
            if q.isEmpty { state = .idle; results = [] }
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            await runSearch(q)
        }
    }

    private func triggerSearch() {
        searchTask?.cancel()
        suggestTask?.cancel()
        suggestions = []
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        rememberSearch(q)
        Task { await runSearch(q) }
    }

    private func runSearch(_ q: String) async {
        guard !q.isEmpty else { state = .idle; return }
        if !env.tmdb.hasKey { state = .noKey; return }
        state = .searching
        correctedQuery = nil
        let found = await env.catalog.search(q)
        if !found.isEmpty {
            results = found
            state = .results
            return
        }
        for candidate in SearchCorrector.corrections(for: q) {
            let retry = await env.catalog.search(candidate)
            if !retry.isEmpty {
                results = retry
                correctedQuery = candidate
                state = .results
                return
            }
        }
        results = []
        state = .empty
    }

    private func runAISearch() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return }
        guard AISearchService.isConfigured else {
            aiError = "AI search isn't set up. Add your Cloudflare Worker URL in Settings ▸ AI Search."
            return
        }
        searchTask?.cancel(); suggestTask?.cancel(); suggestions = []
        searchFocused = false
        aiSearching = true
        state = .searching
        rememberSearch(q)
        do {
            let found = try await env.aiSearch.search(q)
            results = found
            state = found.isEmpty ? .empty : .results
        } catch {
            aiError = (error as? LocalizedError)?.errorDescription ?? "AI search failed."
            state = results.isEmpty ? .idle : .results
        }
        aiSearching = false
    }
}
