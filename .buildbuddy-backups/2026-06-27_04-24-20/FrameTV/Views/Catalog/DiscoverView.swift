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
    @State private var watchlist: [CatalogItem] = []
    @State private var state: ViewState = .idle
    @State private var hasTMDBKey = false
    @State private var searchTask: Task<Void, Never>?

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

                    switch state {
                    case .idle:
                        if !watchlist.isEmpty { watchlistSection }
                        else { hint }
                    case .searching:
                        LoadingView(message: "Searching…").frame(height: 300)
                    case .results:
                        grid(results)
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
        }
        .task { await onAppear() }
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
                .onSubmit { triggerSearch() }
                .onChange(of: query) { _, _ in debounceSearch() }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
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
                .buttonStyle(.plain)
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
        Task { await runSearch(query.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private func runSearch(_ q: String) async {
        guard !q.isEmpty else { state = .idle; return }
        if !(await env.tmdb.hasKey) { state = .noKey; return }
        state = .searching
        let found = await env.catalog.search(q)
        results = found
        state = found.isEmpty ? .empty : .results
    }
}
