//
//  FixMatchView.swift
//  FrameTV
//
//  Lets the user correct the metadata match for a library item (wrong poster, wrong
//  show, wrong episode). Searches the metadata provider and applies the chosen match's
//  title, artwork, and content id to the item, then remembers it via the library.
//  Especially useful for local/SMB files whose filenames matched the wrong title.
//

import SwiftUI

struct FixMatchView: View {
    let item: MediaItem
    var onApplied: (() -> Void)? = nil

    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var results: [CatalogItem] = []
    @State private var state: State = .idle
    @State private var applyingID: String?

    enum State: Equatable { case idle, searching, results, empty, noKey }

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text("Fix Match")
                        .font(Theme.Font.screenTitle())
                        .screenTitleStyle()
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("Currently matched as “\(item.title)”. Search for the correct title and choose it to fix the poster and details.")
                        .font(.appFont(18))
                        .foregroundStyle(Theme.Colors.textSecondary)

                    searchField

                    switch state {
                    case .idle:
                        EmptyView()
                    case .searching:
                        LoadingView(message: "Searching…").frame(height: 160)
                    case .results:
                        ForEach(results) { match in
                            matchRow(match)
                        }
                    case .empty:
                        Text("No matches found. Try a different title.")
                            .font(.appFont(18))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    case .noKey:
                        Text("Add a TMDB key in Settings ▸ Metadata & Accounts to search for matches.")
                            .font(.appFont(18))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
                .padding(Theme.Spacing.edge)
                .frame(maxWidth: Theme.contentMaxWidth(1000), alignment: .leading)
            }
        }
        .onAppear {
            // Seed the search with the item's current title for convenience.
            if query.isEmpty { query = item.seriesTitle ?? item.title }
        }
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.Colors.textTertiary)
            TextField("Search titles", text: $query)
                .textFieldStyle(.plain)
                .font(.appFont(20))
                .foregroundStyle(Theme.Colors.textPrimary)
                .onSubmit { Task { await runSearch() } }
            FocusableButton(title: "Search", systemImage: "magnifyingglass") {
                Task { await runSearch() }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func matchRow(_ match: CatalogItem) -> some View {
        Button { Task { await apply(match) } } label: {
            HStack(spacing: Theme.Spacing.md) {
                PosterImage(url: match.posterURL, width: 60, height: 90)
                VStack(alignment: .leading, spacing: 4) {
                    Text(match.title)
                        .font(.appFont(20, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    HStack(spacing: Theme.Spacing.sm) {
                        if let year = match.year { Text(String(year)) }
                        Text(match.isSeries ? "Series" : "Movie")
                        if let rating = match.rating, rating > 0 {
                            Label(String(format: "%.1f", rating), systemImage: "star.fill")
                        }
                    }
                    .font(.appFont(15))
                    .foregroundStyle(Theme.Colors.textTertiary)
                }
                Spacer()
                if applyingID == match.id {
                    ProgressView().tint(Theme.Colors.accent)
                } else {
                    Image(systemName: "checkmark.circle")
                        .font(.appFont(26))
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
            .padding(.vertical, Theme.Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func runSearch() async {
        guard env.tmdb.hasKey else { state = .noKey; return }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        state = .searching
        let found = (try? await env.tmdb.search(q)) ?? []
        results = found
        state = found.isEmpty ? .empty : .results
    }

    private func apply(_ match: CatalogItem) async {
        applyingID = match.id
        var updated = item
        updated.title = match.title
        updated.contentID = match.contentID
        if let poster = match.posterURL { updated.posterURL = poster }
        if match.backdropURL != nil { updated.backdropURL = match.backdropURL }
        if match.isSeries { updated.seriesTitle = match.title }
        library.update(updated)
        applyingID = nil
        onApplied?()
        dismiss()
    }
}
