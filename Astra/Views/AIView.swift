//
//  AIView.swift
//  Astra
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

    @State private var capability: AISearchService.Capability = .discover
    @State private var prompt = ""
    @State private var catalogResults: [CatalogItem] = []
    @State private var libraryResults: [MediaItem] = []
    @State private var state: ViewState = .idle
    @State private var lastPrompt = ""
    @State private var savedMessage: String?
    @FocusState private var promptFocused: Bool

    enum ViewState: Equatable { case idle, working, results, empty, error(String) }

    private var columns: [GridItem] { Theme.posterGridColumns }

    private var suggestions: [String] {
        switch capability {
        case .discover:
            return ["Dark sci-fi thrillers", "Comfort TV shows",
                    "Mind-bending movies like Inception", "Feel-good 90s comedies"]
        case .librarySearch:
            return ["Something funny but not stupid", "A movie with aliens",
                    "Something short to watch tonight"]
        case .buildCollection:
            return ["Best heist movies", "Cozy autumn watches", "Great courtroom dramas"]
        case .buildLineup:
            return ["Friday night, 3 films", "A horror double feature", "Date night picks"]
        case .similarTo:
            return ["More like Inception", "More like Breaking Bad", "More like Studio Ghibli"]
        case .moodMatch:
            return ["I feel nostalgic", "I want to be scared", "Something uplifting"]
        case .franchiseOrder:
            return ["The MCU in story order", "Star Wars chronological", "The Conjuring universe"]
        case .hiddenGems:
            return ["Underrated 2010s sci-fi", "Overlooked thrillers", "Quiet indie dramas"]
        case .familyFriendly:
            return ["Fun for a 7 year old", "Whole-family movie night", "Gentle bedtime shows"]
        case .quickWatch:
            return ["Under 100 minutes", "A single tight episode", "Quick laughs"]
        case .surpriseMe:
            return ["Surprise me", "Something I'd never pick", "Dealer's choice"]
        case .fillGaps:
            return ["Classics I should have seen", "Essential 90s films", "Must-see documentaries"]
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.Colors.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        header
                        capabilityPicker
                        promptField
                        suggestionChips
                        if let savedMessage {
                            Label(savedMessage, systemImage: "checkmark.circle.fill")
                                .font(.appFont(15, weight: .medium))
                                .foregroundStyle(Theme.Colors.accent)
                        }
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

    private var capabilityPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(AISearchService.Capability.allCases) { cap in
                    Button {
                        capability = cap
                        resetResults()
                    } label: {
                        Label(cap.rawValue, systemImage: cap.systemImage)
                            .font(.appFont(15, weight: .semibold))
                            .foregroundStyle(capability == cap ? .black : Theme.Colors.textPrimary)
                            .padding(.vertical, Theme.Spacing.sm)
                            .padding(.horizontal, Theme.Spacing.md)
                            .background(
                                Capsule().fill(capability == cap
                                               ? Theme.Colors.accent
                                               : Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(AstraChipButtonStyle())
                }
            }
            .padding(.horizontal, Theme.Spacing.edge)
        }
        .padding(.horizontal, -Theme.Spacing.edge)
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
            .astraRowStyle()
            .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var promptPlaceholder: String { capability.placeholder }

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
            if !AISearchService.isConfigured && !capability.searchesLibrary {
                notConfiguredCard
            }
        case .working:
            HStack(spacing: Theme.Spacing.md) {
                ProgressView().tint(Theme.Colors.accent)
                Text(capability.searchesLibrary ? "Searching your library…" : "Building your picks…")
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
                if !capability.searchesLibrary {
                    saveActions
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
                message: capability.searchesLibrary
                    ? "Nothing in your library matched that. Try different words."
                    : "AI couldn't turn that into titles we could find. Try rephrasing."
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
        catalogResults = []; libraryResults = []; state = .idle; lastPrompt = ""; savedMessage = nil
    }

    private func run() {
        let q = prompt.trimmingCharacters(in: .whitespaces)
        // Surprise Me can run with no text; everything else needs a prompt.
        guard !q.isEmpty || capability == .surpriseMe else { return }
        promptFocused = false
        lastPrompt = q
        savedMessage = nil
        state = .working
        Task {
            if capability.searchesLibrary {
                let items = await env.aiSearch.searchLibrary(q, in: library.items)
                libraryResults = items
                state = items.isEmpty ? .empty : .results
            } else {
                do {
                    let items = try await env.aiSearch.run(capability, userText: q, limit: 24)
                    catalogResults = items
                    state = items.isEmpty ? .empty : .results
                } catch {
                    let msg = (error as? LocalizedError)?.errorDescription
                        ?? "AI isn't set up. Add your Cloudflare Worker URL in Settings."
                    state = .error(msg)
                }
            }
        }
    }

    // MARK: - Save actions (build / add)

    /// Actions that turn AI results into things in the app: save as a collection, add
    /// every result to the library, or queue them all up.
    @ViewBuilder private var saveActions: some View {
        if capability.producesCollection, !catalogResults.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    Button {
                        saveAsCollection()
                    } label: {
                        Label("Save as Collection", systemImage: "rectangle.stack.badge.plus")
                            .font(.appFont(15, weight: .semibold))
                    }
                    .buttonStyle(AstraChipButtonStyle())

                    Button {
                        addAllToLibrary()
                    } label: {
                        Label("Add All to Library", systemImage: "plus.square.on.square")
                            .font(.appFont(15, weight: .semibold))
                    }
                    .buttonStyle(AstraChipButtonStyle())

                    Button {
                        queueAll()
                    } label: {
                        Label("Add All to Queue", systemImage: "text.badge.plus")
                            .font(.appFont(15, weight: .semibold))
                    }
                    .buttonStyle(AstraChipButtonStyle())
                }
            }
            .padding(.bottom, Theme.Spacing.xs)
        }
    }

    /// Converts the current catalog results to library items (metadata only; a source
    /// is resolved when the user plays them).
    private func resultItems() -> [MediaItem] {
        catalogResults.map { $0.asLibraryItem() }
    }

    private func saveAsCollection() {
        let name = lastPrompt.isEmpty ? capability.rawValue : lastPrompt
        let collection = library.createCollection(name: name, systemImage: capability.systemImage)
        for item in resultItems() {
            library.add(item)
            library.addToCollection(collection.id, item: item)
        }
        savedMessage = "Saved \(catalogResults.count) to the “\(name)” collection."
    }

    private func addAllToLibrary() {
        let items = resultItems()
        for item in items { library.add(item) }
        savedMessage = "Added \(items.count) to your library."
    }

    private func queueAll() {
        let items = resultItems()
        for item in items {
            library.add(item)
            library.addToQueue(item)
        }
        savedMessage = "Queued \(items.count) title\(items.count == 1 ? "" : "s")."
    }
}
