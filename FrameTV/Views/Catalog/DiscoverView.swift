//
//  DiscoverView.swift
//  FrameTV
//
//  Search and discovery. The user searches by title (TMDB) and taps a result to
//  open its detail screen. When a TMDB key isn't set, it explains how to add one.
//  Optionally shows the user's Trakt watchlist as a starting row.
//

import SwiftUI

struct DiscoverView: View {
    @Binding var path: NavigationPath
    @EnvironmentObject private var env: AppEnvironment

    @State private var query = ""
    @State private var results: [CatalogItem] = []
    /// Set when results came from an auto-corrected spelling, to show a note.
    @State private var correctedQuery: String?
    @State private var watchlist: [CatalogItem] = []
    @State private var state: ViewState = .idle
    @State private var hasTMDBKey = false
    @State private var searchTask: Task<Void, Never>?

    // Predictive search.
    @State private var suggestions: [CatalogItem] = []
    @State private var suggestTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool
    @AppStorage("discover.recentSearches") private var recentSearchesRaw = ""
    @StateObject private var shelfStore = HomeShelfStore.shared
    @State private var aiSearching = false
    @State private var aiError: String?
    /// Bumped each time Discover appears so its shelves reshuffle and refresh.
    @State private var discoverRefreshToken = 0

    @ViewBuilder
    private var discoverShelves: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.rowGap) {
            NavigationLink(value: DiscoverRoute.liveTV) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.appFont(22, weight: .semibold))
                    Text("Live TV")
                        .font(.appFont(20, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right").font(.appFont(16))
                }
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.vertical, Theme.Spacing.xs)
                .contentShape(Rectangle())
            }
            .frameRowStyle()

            if shelfStore.enabledShelves.isEmpty {
                hint
            } else {
                // Shelf rows manage their own horizontal insets, so offset them back
                // out of this view's edge padding.
                ForEach(shelfStore.enabledShelves) { shelf in
                    CatalogShelfRow(shelf: shelf, showSourceLabel: true, variant: .discover)
                        .id("\(shelf.id)-\(discoverRefreshToken)")
                        .padding(.horizontal, -Theme.Spacing.edge)
                }
            }
        }
    }

    enum DiscoverRoute: Hashable { case liveTV }

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

    enum ViewState: Equatable { case idle, searching, results, empty, noKey }

    private let columns = [GridItem(.adaptive(minimum: Theme.CardSize.posterWidth * 0.95),
                                    spacing: Theme.Spacing.md)]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text("Discover")
                        .font(Theme.Font.screenTitle())
                        .screenTitleStyle()
                        .foregroundStyle(Theme.Colors.textPrimary)

                    searchField

                    suggestionsView

                    switch state {
                    case .idle:
                        discoverShelves
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
                            grid(results)
                        }
                    case .empty:
                        EmptyStateView(systemImage: "magnifyingglass",
                                       title: "No results",
                                       message: "Nothing matched “\(query)”. Try a different title.")
                            .frame(height: 360)
                    case .noKey:
                        noKeyState
                    }
                }
                .padding(Theme.Spacing.edge)
                .frame(maxWidth: Theme.contentMaxWidth(1500), alignment: .leading)
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationDestination(for: CatalogItem.self) { item in
                ContentDetailView(item: item)
            }
            .navigationDestination(for: DiscoverRoute.self) { route in
                switch route {
                case .liveTV: LiveTVView()
                }
            }
            .alert("AI Search", isPresented: .constant(aiError != nil)) {
                Button("OK") { aiError = nil }
            } message: {
                Text(aiError ?? "")
            }
        }
        .task { await onAppear() }
        .onAppear { discoverRefreshToken += 1 }
        .dismissKeyboardOnTap()
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.appFont(24))
                .foregroundStyle(Theme.Colors.textSecondary)
            TextField("Search movies and shows", text: $query)
                .textFieldStyle(.plain)
                .font(.appFont(26))
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
                .frameIconStyle()
            }
            // AI (natural-language) search via the user's Worker.
            Button {
                Task { await runAISearch() }
            } label: {
                Image(systemName: "sparkles")
                    .font(.appFont(22))
                    .foregroundStyle(aiSearching ? Theme.Colors.textTertiary : Theme.Colors.accent)
            }
            .frameIconStyle()
            .disabled(aiSearching || query.trimmingCharacters(in: .whitespaces).count < 2)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    /// Predictive suggestions: recent searches when empty/short, live title matches
    /// as the user types. Tapping one fills the field and runs the search.
    @ViewBuilder
    private var suggestionsView: some View {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if searchFocused && q.count < 2 && !recentSearches.isEmpty {
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
                    .buttonStyle(FrameListRowStyle())
                }
                if !recentSearches.isEmpty {
                    Button("Clear recent searches") { recentSearchesRaw = "" }
                        .font(.appFont(16))
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(Theme.Spacing.md)
                }
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
                    .buttonStyle(FrameListRowStyle())
                }
            }
            .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
    }

    private func debounceSuggest() {
        suggestTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { suggestions = []; return }
        suggestTask = Task {
            // Shorter debounce than full search so suggestions feel instant.
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            let found = await env.catalog.search(q)
            guard !Task.isCancelled else { return }
            await MainActor.run { suggestions = found }
        }
    }

    private var hint: some View {
        Text("Search for a movie or show to find streams from your installed addons.")
            .font(.appFont(22))
            .foregroundStyle(Theme.Colors.textTertiary)
            .padding(.top, Theme.Spacing.md)
    }

    private var noKeyState: some View {
        EmptyStateView(
            systemImage: "key",
            title: "Add a TMDB key to search",
            message: "Search needs a free TMDB API key. Add one in Settings ▸ Metadata & Accounts, or drop a FrameTVConfig.json next to the app."
        )
        .frame(height: 400)
    }

    // MARK: - Watchlist

    private var watchlistSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Your Trakt Watchlist")
                .font(Theme.Font.sectionTitle())
                .foregroundStyle(Theme.Colors.textPrimary)
            grid(watchlist)
        }
    }

    // MARK: - Grid

    private func grid(_ items: [CatalogItem]) -> some View {
        LazyVGrid(columns: columns, spacing: Theme.Spacing.lg) {
            ForEach(items) { item in
                NavigationLink(value: item) {
                    posterCard(item)
                }
                .buttonStyle(FrameListRowStyle())
            }
        }
        // Warm poster images ahead of scroll so the grid stays smooth.
        .onAppear {
            ImageLoader.shared.prefetch(items.compactMap(\.posterURL))
        }
    }

    /// Shimmering placeholder grid shown while a search is in flight.
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
            PosterImage(url: item.posterURL, width: Theme.CardSize.posterWidth * 0.95, height: Theme.CardSize.posterWidth * 0.95 * 1.5)
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

    private func onAppear() async {
        hasTMDBKey = await env.tmdb.hasKey
        if state == .noKey && hasTMDBKey { state = .idle }
        // Load watchlist if Trakt is connected.
        if await env.trakt.isAuthenticated {
            watchlist = (try? await env.trakt.watchlist()) ?? []
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
        if !(await env.tmdb.hasKey) { state = .noKey; return }
        state = .searching
        correctedQuery = nil
        let found = await env.catalog.search(q)
        if !found.isEmpty {
            results = found
            state = .results
            return
        }
        // No results — try typo-tolerant corrections before giving up.
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
