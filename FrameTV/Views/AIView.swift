//
//  AIView.swift
//  FrameTV
//
//  The AI tab. One place for AI-assisted discovery and library search:
//   - Generate a themed shelf or playlist from a prompt ("dark sci-fi thrillers",
//     "5-movie Friday night lineup"), resolved to real titles via TMDB.
//   - Search your own library by vibe or fuzzy memory ("the show I started last week",
//     "something funny but not stupid").
//
//  Everything routes through AISearchService and the user's Cloudflare Worker. When the
//  Worker isn't configured, the screen explains how to set it up and library search
//  still works with a local keyword fallback.
//

import SwiftUI

struct AIView: View {
    @Binding var path: NavigationPath
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var nav: NavigationCoordinator
    @EnvironmentObject private var library: LibraryStore

    enum Mode: String, CaseIterable, Identifiable {
        case discover = "Discover"
        case library = "My Library"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .discover
    @State private var prompt = ""
    @State private var catalogResults: [CatalogItem] = []
    @State private var libraryResults: [MediaItem] = []
    @State private var state: ViewState = .idle
    @State private var lastPrompt = ""
    @FocusState private var promptFocused: Bool

    enum ViewState: Equatable { case idle, working, results, empty, error(String) }

    private var columns: [GridItem] { Theme.posterGridColumns }

    private var suggestions: [String] {
        switch mode {
        case .discover:
            return ["Dark sci-fi thrillers",
                    "A 5-movie Friday night lineup",
                    "Comfort TV shows",
                    "Mind-bending movies like Inception",
                    "Feel-good 90s comedies"]
        case .library:
            return ["Something funny but not stupid",
                    "The show I started recently",
                    "A movie with aliens",
                    "Something short to watch tonight"]
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.Colors.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        header
                        modePicker
                        promptField
                        suggestionChips
                        resultsSection
                    }
                    .padding(Theme.Spacing.edge)
                    .frame(maxWidth: Theme.contentMaxWidth(1500), alignment: .leading)
                }
            }
            .navigationDestination(for: CatalogItem.self) { item in
                ContentDetailView(item: item)
            }
            .navigationDestination(item: $playerItem) { item in
                PlayerView(item: item)
            }
        }
    }

    @State private var playerItem: MediaItem?

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("AI", systemImage: "sparkles")
                .font(Theme.Font.screenTitle())
                .screenTitleStyle()
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Describe what you're in the mood for, and let AI build it.")
                .font(.appFont(18))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private var modePicker: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(Mode.allCases) { m in
                FocusableButton(title: m.rawValue, prominent: m == mode) {
                    mode = m
                    resetResults()
                }
                .frame(maxWidth: 220)
            }
        }
    }

    private var promptField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "sparkle.magnifyingglass")
                .foregroundStyle(Theme.Colors.accent)
            TextField(promptPlaceholder, text: $prompt)
                .focused($promptFocused)
                .font(.appFont(20))
                .submitLabel(.search)
                .onSubmit { run() }
                .foregroundStyle(Theme.Colors.textPrimary)
            if !prompt.isEmpty {
                Button { prompt = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            Button { run() } label: {
                Text("Go").font(.appFont(18, weight: .bold))
            }
            .frameRowStyle()
            .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var promptPlaceholder: String {
        mode == .discover ? "e.g. dark sci-fi thrillers" : "e.g. something funny but not stupid"
    }

    private var suggestionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(suggestions, id: \.self) { s in
                    Button {
                        prompt = s
                        run()
                    } label: {
                        Text(s)
                            .font(.appFont(16))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm)
                            .background(Theme.Colors.card, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        switch state {
        case .idle:
            if !AISearchService.isConfigured && mode == .discover {
                notConfiguredCard
            }
        case .working:
            HStack(spacing: Theme.Spacing.md) {
                ProgressView().tint(Theme.Colors.accent)
                Text(mode == .discover ? "Building your picks…" : "Searching your library…")
                    .font(.appFont(18))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding(.top, Theme.Spacing.lg)
        case .results:
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if !lastPrompt.isEmpty {
                    Text("Results for “\(lastPrompt)”")
                        .font(.appFont(20, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                if mode == .discover {
                    LazyVGrid(columns: columns, spacing: Theme.Spacing.lg) {
                        ForEach(catalogResults) { item in
                            NavigationLink(value: item) {
                                catalogCard(item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    LazyVGrid(columns: columns, spacing: Theme.Spacing.lg) {
                        ForEach(libraryResults) { item in
                            MediaCard(item: item) { playerItem = item }
                        }
                    }
                }
            }
        case .empty:
            EmptyStateView(
                systemImage: "sparkles",
                title: "No matches",
                message: mode == .discover
                    ? "AI couldn't turn that into titles we could find. Try rephrasing."
                    : "Nothing in your library matched that. Try different words."
            )
            .frame(height: 320)
        case .error(let msg):
            EmptyStateView(systemImage: "exclamationmark.triangle",
                           title: "AI search unavailable",
                           message: msg,
                           actionTitle: "Set Up AI",
                           action: { nav.selection = .settings })
                .frame(height: 320)
        }
    }

    private var notConfiguredCard: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "sparkles")
                .font(.appFont(52))
                .foregroundStyle(Theme.Colors.accent)
            Text("Set up AI to build shelves and playlists")
                .font(.appFont(22, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .multilineTextAlignment(.center)
            Text("AI Discover uses your own Cloudflare Worker. Add its URL in Settings to generate themed shelves and playlists. Library search below works without it.")
                .font(.appFont(17))
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
            FocusableButton(title: "Set Up AI", systemImage: "gearshape", prominent: true) {
                nav.selection = .settings
            }
            .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.lg)
    }

    // MARK: - Cards

    /// A poster + title card for an AI-suggested catalog item.
    private func catalogCard(_ item: CatalogItem) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            PosterImage(url: item.posterURL,
                        width: Theme.CardSize.posterWidth,
                        height: Theme.CardSize.posterHeight)
            Text(item.title)
                .font(.appFont(17, weight: .medium))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .frame(width: Theme.CardSize.posterWidth, alignment: .leading)
        }
    }

    // MARK: - Actions

    private func resetResults() {
        catalogResults = []; libraryResults = []; state = .idle; lastPrompt = ""
    }

    private func run() {
        let q = prompt.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        promptFocused = false
        lastPrompt = q
        state = .working
        Task {
            switch mode {
            case .discover:
                do {
                    let items = try await env.aiSearch.resolveTitles(for: q, limit: 24)
                    catalogResults = items
                    state = items.isEmpty ? .empty : .results
                } catch {
                    let msg = (error as? LocalizedError)?.errorDescription
                        ?? "AI isn't set up. Add your Cloudflare Worker URL in Settings."
                    state = .error(msg)
                }
            case .library:
                let items = await env.aiSearch.searchLibrary(q, in: library.items)
                libraryResults = items
                state = items.isEmpty ? .empty : .results
            }
        }
    }
}
