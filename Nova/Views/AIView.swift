//
//  AIView.swift
//  Nova
//
//  The AI tab. Opens on a browsable menu of every AI feature, organized into
//  groups, so everything AI can do is visible at a glance — no typing required to
//  get started. Tap a feature, tap a ready-made suggestion (or write your own
//  prompt), and the results can be saved as a Home shelf, a collection, library
//  additions, or a queue in one tap.
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
    @State private var collectionSuggestions: [AISearchService.CollectionSuggestion] = []
    @State private var state: ViewState = .idle
    @State private var lastPrompt = ""
    @State private var playerItem: MediaItem?
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
        case .buildShelf:
            return ["Neo-noir crime", "Cozy sci-fi", "Feel-good comedies"]
        case .doubleFeature:
            return ["A horror double bill", "Two space epics", "Classic and remake"]
        case .bingeQueue:
            return ["Bingeable sci-fi series", "Addictive crime dramas", "Bingeable sitcoms"]
        case .decade:
            return ["The best of the 90s", "Essential 80s films", "2010s standouts"]
        case .director:
            return ["Denis Villeneuve films", "Christopher Nolan movies", "Studio Ghibli"]
        case .criticPicks:
            return ["Award-winning dramas", "Best Picture winners", "Critically acclaimed sci-fi"]
        case .genreBlend:
            return ["Romantic comedies with sci-fi", "Horror comedies", "Action thrillers with heart"]
        case .foreign:
            return ["Korean thrillers", "French New Wave", "Japanese animation"]
        case .comfortWatch:
            return ["Cozy rewatchable shows", "Comfort movies", "Easy background TV"]
        case .soundtrack:
            return ["Films with iconic scores", "Great musicals", "Movies with killer soundtracks"]
        case .basedOnBooks:
            return ["Great book adaptations", "Novels made into films", "Book-to-series adaptations"]
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.Colors.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        header
                        if !AISearchService.isConfigured {
                            setupBanner
                        }
                        capabilityPicker
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
            .fullScreenCover(item: $playerItem) { item in
                // Present the player as a full-screen cover so no tab bar, sidebar,
                // or mini-bar remains visible during playback on any platform.
                NavigationStack { PlayerView(item: item) }
            }
        }
    }

    /// One compact chooser replaces the long feature-card directory. The prompt
    /// remains visible, so changing what AI should do never interrupts the chat.
    private var capabilityPicker: some View {
        Menu {
            Picker("AI task", selection: $capability) {
                ForEach(AISearchService.Capability.Category.allCases) { category in
                    Section(category.rawValue) {
                        ForEach(AISearchService.Capability.allCases.filter { $0.category == category }) { cap in
                            Label(cap.rawValue, systemImage: cap.systemImage).tag(cap)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: capability.systemImage)
                    .foregroundStyle(Theme.Colors.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(capability.rawValue)
                        .font(.appFont(18, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(capability.blurb)
                        .font(.appFont(14))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.card,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(NovaChipButtonStyle())
        .accessibilityLabel("AI task, \(capability.rawValue)")
        .onChange(of: capability) { _, _ in resetResults() }
    }

    // MARK: - Headers

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("AI", systemImage: "sparkles")
                .font(Theme.Font.screenTitle())
                .screenTitleStyle()
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Everything AI can do, in one place. Pick a feature to start — most need just one tap.")
                .font(.appFont(18))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    // MARK: - Prompt input

    private var promptField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "sparkle.magnifyingglass")
                .foregroundStyle(Theme.Colors.accent)
            TextField(promptPlaceholder, text: $prompt, axis: .vertical)
                .focused($promptFocused)
                .font(.appFont(20))
                .lineLimit(2...5)
                .submitLabel(.search)
                .onSubmit { run() }
                .foregroundStyle(Theme.Colors.textPrimary)
            if !prompt.isEmpty {
                Button { prompt = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                // Accessibility: icon-only clear button needs a spoken name.
                .accessibilityLabel("Clear prompt")
            }
            Button { run() } label: {
                Text("Go").font(.appFont(18, weight: .bold))
            }
            .novaRowStyle()
            .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty && capability != .surpriseMe)
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
                    // Chip style gives these a proper tvOS focus/press effect,
                    // matching every other chip in the app.
                    .buttonStyle(NovaChipButtonStyle())
                }
            }
        }
    }

    // MARK: - Results

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
                if !collectionSuggestions.isEmpty {
                    collectionProposalSection
                } else if !capability.searchesLibrary {
                    saveActions
                    LazyVGrid(columns: columns, spacing: Theme.Spacing.lg) {
                        ForEach(catalogResults) { item in
                            NavigationLink(value: item) {
                                catalogCard(item)
                            }
                            .buttonStyle(.plain)
                            .overlay(alignment: .topTrailing) {
                                quickAddButton(item)
                            }
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
            ContentStateView(state: .empty(
                systemImage: "sparkles",
                title: "No matches",
                message: capability.searchesLibrary
                    ? "Nothing in your library matched that. Try different words."
                    : "AI couldn't turn that into titles we could find. Try rephrasing."))
                .frame(height: 320)
        case .error(let msg):
            ContentStateView(state: .error(
                title: "AI search unavailable",
                message: msg,
                actionTitle: "Set Up AI",
                action: { nav.selection = .settings }))
                .frame(height: 320)
        }
    }

    /// A compact banner on the menu screen when the Worker isn't configured yet.
    /// Library search still works without it, so this informs rather than blocks.
    private var setupBanner: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "wand.and.stars")
                .font(.appFont(28))
                .foregroundStyle(Theme.Colors.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Set up AI to unlock every feature")
                    .font(.appFont(17, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Add your Cloudflare Worker URL in Settings. Library Search works without it.")
                    .font(.appFont(14))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            Button("Set Up") { nav.selection = .settings }
                .font(.appFont(15, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent)
                .buttonStyle(NovaChipButtonStyle())
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.card,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
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
            Text("AI Discover uses your own Cloudflare Worker. Add its URL in Settings to generate themed shelves and playlists. Library search works without it.")
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

    /// A poster + title card for an AI-suggested catalog item (shared component).
    private func catalogCard(_ item: CatalogItem) -> some View {
        CatalogPosterCard(item: item)
    }

    /// One-tap add for a single AI result, without opening its detail screen.
    private func quickAddButton(_ item: CatalogItem) -> some View {
        Button {
            library.add(item.asLibraryItem())
            ToastCenter.shared.show("Added “\(item.title)”")
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.appFont(26, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Theme.Colors.accent)
                .shadow(color: .black.opacity(0.5), radius: 4)
        }
        .buttonStyle(.plain)
        .padding(6)
        .accessibilityLabel("Add \(item.title) to library")
    }

    // MARK: - Actions

    private func resetResults() {
        catalogResults = []; libraryResults = []; collectionSuggestions = []
        state = .idle; lastPrompt = ""
        prompt = ""
    }

    private func run() {
        let q = prompt.trimmingCharacters(in: .whitespaces)
        // Surprise Me can run with no text; everything else needs a prompt.
        guard !q.isEmpty || capability == .surpriseMe else { return }
        promptFocused = false
        lastPrompt = q
        state = .working
        Task {
            if capability.searchesLibrary {
                let items = await env.aiSearch.searchLibrary(q, in: library.collapseToShow(library.items))
                libraryResults = library.collapseToShow(items)
                state = libraryResults.isEmpty ? .empty : .results
            } else {
                do {
                    let requestedCollections = AISearchService.requestedCollectionCount(in: q)
                    if capability == .buildCollection, requestedCollections > 1 {
                        let suggestions = try await env.aiSearch.buildCollections(
                            for: q,
                            count: requestedCollections
                        )
                        collectionSuggestions = suggestions
                        catalogResults = []
                        state = suggestions.isEmpty ? .empty : .results
                    } else {
                        let items = try await env.aiSearch.run(capability, userText: q, limit: 24)
                        catalogResults = items
                        collectionSuggestions = []
                        state = items.isEmpty ? .empty : .results
                    }
                } catch {
                    let msg = (error as? LocalizedError)?.errorDescription
                        ?? "AI isn't set up. Add your Cloudflare Worker URL in Settings."
                    state = .error(msg)
                }
            }
        }
    }

    private var collectionProposalSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("\(collectionSuggestions.count) collection previews")
                .font(.appFont(18, weight: .semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
            ForEach(collectionSuggestions) { suggestion in
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.name)
                                .font(.appFont(20, weight: .semibold))
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text("\(suggestion.items.count) titles")
                                .font(.appFont(14))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Spacer()
                        Button("Dismiss") { dismissCollectionSuggestion(suggestion.id) }
                            .buttonStyle(NovaChipButtonStyle())
                        Button("Save") { saveCollectionSuggestion(suggestion) }
                            .buttonStyle(NovaChipButtonStyle())
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Spacing.sm) {
                            ForEach(suggestion.items.prefix(6)) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    CachedAsyncImage(url: item.posterURL, maxPixel: 360) { image in
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        RoundedRectangle(cornerRadius: Theme.Radius.card)
                                            .fill(Theme.Colors.backgroundElevated)
                                    }
                                    .frame(width: 84, height: 126)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
                                    Text(item.title)
                                        .font(.appFont(12, weight: .medium))
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                        .lineLimit(1)
                                        .frame(width: 84, alignment: .leading)
                                }
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.card,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            }
        }
    }

    private func saveCollectionSuggestion(_ suggestion: AISearchService.CollectionSuggestion) {
        let collection = library.createCollection(name: suggestion.name, systemImage: capability.systemImage)
        for item in suggestion.items {
            let libraryItem = item.asLibraryItem()
            library.add(libraryItem)
            library.addToCollection(collection.id, item: libraryItem)
        }
        collectionSuggestions.removeAll { $0.id == suggestion.id }
        ToastCenter.shared.show("Saved \(suggestion.items.count) to “\(suggestion.name)”")
    }

    private func dismissCollectionSuggestion(_ id: UUID) {
        collectionSuggestions.removeAll { $0.id == id }
        if collectionSuggestions.isEmpty { state = .idle }
    }

    // MARK: - Save actions (build / add)

    /// Actions that turn AI results into things in the app: pin them to Home as a
    /// living AI shelf, save them as a collection, add every result to the library,
    /// or queue them all up. Building shelves and collections is one tap from here.
    @ViewBuilder private var saveActions: some View {
        if capability.producesCollection, !catalogResults.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    Button {
                        saveAsShelf()
                    } label: {
                        Label("Add as Home Shelf", systemImage: "rectangle.grid.1x2")
                            .font(.appFont(15, weight: .semibold))
                    }
                    .buttonStyle(NovaChipButtonStyle())

                    Button {
                        saveAsCollection()
                    } label: {
                        Label("Save as Collection", systemImage: "rectangle.stack.badge.plus")
                            .font(.appFont(15, weight: .semibold))
                    }
                    .buttonStyle(NovaChipButtonStyle())

                    Button {
                        addAllToLibrary()
                    } label: {
                        Label("Add All to Library", systemImage: "plus.square.on.square")
                            .font(.appFont(15, weight: .semibold))
                    }
                    .buttonStyle(NovaChipButtonStyle())

                    Button {
                        queueAll()
                    } label: {
                        Label("Add All to Queue", systemImage: "text.badge.plus")
                            .font(.appFont(15, weight: .semibold))
                    }
                    .buttonStyle(NovaChipButtonStyle())
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

    /// Pins the current prompt to Home as a living AI shelf. The shelf stores the
    /// specialized instruction, so it reloads fresh picks for the same idea over time.
    private func saveAsShelf() {
        let name = (lastPrompt.isEmpty ? capability.rawValue : lastPrompt).capitalized
        let shelfPrompt = capability.instruction(for: lastPrompt)
        HomeShelfStore.shared.shelves.append(
            ShelfConfig(kind: .aiShelf(prompt: shelfPrompt), title: name)
        )
        ToastCenter.shared.show("Added “\(name)” to Home")
    }

    private func saveAsCollection() {
        let name = lastPrompt.isEmpty ? capability.rawValue : lastPrompt
        let collection = library.createCollection(name: name, systemImage: capability.systemImage)
        for item in resultItems() {
            library.add(item)
            library.addToCollection(collection.id, item: item)
        }
        ToastCenter.shared.show("Saved \(catalogResults.count) to “\(name)”")
    }

    private func addAllToLibrary() {
        let items = resultItems()
        for item in items { library.add(item) }
        ToastCenter.shared.show("Added \(items.count) to your library")
    }

    private func queueAll() {
        let items = resultItems()
        for item in items {
            library.add(item)
            library.addToQueue(item)
        }
        ToastCenter.shared.show("Queued \(items.count) title\(items.count == 1 ? "" : "s")")
    }
}

// MARK: - New & Hot

/// Nova's editorial catalog destination, reached from Search now that the dedicated
/// tab once again exposes the complete AI feature directory.
struct NewAndHotView: View {
    @Binding var path: NavigationPath
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var nav: NavigationCoordinator
    @StateObject private var reminders = CatalogReminderStore.shared
    @StateObject private var network = NetworkConditionMonitor.shared

    @State private var trending: [CatalogItem] = []
    @State private var newThisWeek: [CatalogItem] = []
    @State private var comingSoon: [CatalogItem] = []
    @State private var popular: [CatalogItem] = []
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var filter: NewHotFilter = .all

    private enum NewHotFilter: String, CaseIterable, Identifiable {
        case all = "Everything", movies = "Movies", shows = "TV Shows", reminders = "Reminders"
        var id: Self { self }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.Colors.appBackground.ignoresSafeArea()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.rowGap) {
                        header
                        if !network.isOnline { offlineBanner }
                        content
                    }
                    .padding(.bottom, Theme.Spacing.xl)
                }
                #if os(iOS)
                .refreshable { await load() }
                #endif
            }
            .navigationDestination(for: CatalogItem.self) { ContentDetailView(item: $0) }
        }
        .task { if trending.isEmpty { await load() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("New & Hot")
                        .font(Theme.Font.screenTitle())
                        .screenTitleStyle()
                    Text("The titles everyone is talking about.")
                        .font(.appFont(17))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                Image(systemName: "sparkles")
                    .font(.appFont(22, weight: .bold))
                    .foregroundStyle(Theme.Colors.accent)
                    .accessibilityHidden(true)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(NewHotFilter.allCases) { option in
                        Button(option.rawValue) { withAnimation(Theme.Motion.spring) { filter = option } }
                            .buttonStyle(NewHotFilterButtonStyle(selected: filter == option))
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.edge)
        .padding(.top, Theme.Spacing.lg)
    }

    @ViewBuilder private var content: some View {
        if !env.tmdb.hasKey {
            setupState
        } else if loading && trending.isEmpty {
            newHotSkeleton
        } else if let errorMessage, trending.isEmpty {
            retryState(errorMessage)
        } else if filter == .reminders {
            let saved = filtered((trending + newThisWeek + comingSoon + popular).uniquedCatalog)
                .filter { reminders.contains($0) }
            if saved.isEmpty {
                EmptyStateView(systemImage: "bell", title: "No reminders yet",
                               message: "Choose Remind Me on a coming-soon title and it will appear here.")
            } else {
                posterGrid(title: "My Reminders", items: saved)
            }
        } else {
            if let hero = filtered(trending).first { editorialHero(hero) }
            rankedRow(Array(filtered(trending).prefix(10)))
            reminderRow(title: "Coming Soon", items: filtered(comingSoon))
            posterRow(title: "New This Week", items: filtered(newThisWeek))
            posterRow(title: "Popular on Nova", items: filtered(popular))
        }
    }

    private var offlineBanner: some View {
        Label("You're offline — showing the catalog already loaded on this device.", systemImage: "wifi.slash")
            .font(.appFont(15, weight: .semibold))
            .foregroundStyle(.white)
            .padding(Theme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.iconGraphite.opacity(0.8), in: RoundedRectangle(cornerRadius: Theme.Radius.button))
            .padding(.horizontal, Theme.Spacing.edge)
    }

    private var setupState: some View {
        EmptyStateView(systemImage: "film.stack", title: "Unlock New & Hot",
                       message: "Add a free TMDB key in Settings to load current movies, shows, artwork, and release picks.",
                       actionTitle: "Open Settings", actionSystemImage: "gearshape") {
            nav.selection = .settings
        }
    }

    private var newHotSkeleton: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            RoundedRectangle(cornerRadius: Theme.Radius.largeCard)
                .fill(Theme.Colors.card).frame(height: Theme.isCompact ? 330 : 460).shimmering()
            ForEach(0..<2, id: \.self) { _ in
                HStack(spacing: Theme.Spacing.md) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: Theme.Radius.card)
                            .fill(Theme.Colors.card)
                            .frame(width: Theme.CardSize.posterWidth * 0.78,
                                   height: Theme.CardSize.posterHeight * 0.78)
                    }
                }.shimmering()
            }
        }.padding(.horizontal, Theme.Spacing.edge)
    }

    private func retryState(_ message: String) -> some View {
        EmptyStateView(systemImage: "exclamationmark.arrow.triangle.2.circlepath", title: "Couldn't refresh",
                       message: message, actionTitle: "Try Again", actionSystemImage: "arrow.clockwise") {
            Task { await load() }
        }
    }

    private func editorialHero(_ item: CatalogItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            CachedAsyncImage(url: item.backdropURL ?? item.posterURL, maxPixel: 1600) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: { Rectangle().fill(Theme.Colors.card).shimmering() }
            .frame(maxWidth: .infinity).frame(height: Theme.isCompact ? 360 : 500).clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.35), .black], startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .leading, endPoint: .trailing)
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("#1 IN NEW & HOT").font(.appFont(13, weight: .black)).tracking(1.1).foregroundStyle(Theme.Colors.accent)
                Text(item.title).font(.appFont(42, weight: .black)).lineLimit(2).minimumScaleFactor(0.65)
                Text(item.overview ?? "A standout pick for your next watch.")
                    .font(.appFont(16)).foregroundStyle(Theme.Colors.textSecondary).lineLimit(3)
                NavigationLink(value: item) {
                    Label("More Info", systemImage: "info.circle.fill")
                        .font(.appFont(17, weight: .bold)).padding(.horizontal, 18).padding(.vertical, 11)
                        .background(.white, in: RoundedRectangle(cornerRadius: Theme.Radius.button)).foregroundStyle(.black)
                }.buttonStyle(.plain)
            }
            .frame(maxWidth: Theme.isCompact ? .infinity : 620, alignment: .leading)
            .padding(Theme.Spacing.edge)
        }
        .frame(height: Theme.isCompact ? 360 : 500)
        .clipped()
    }

    private func rankedRow(_ items: [CatalogItem]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionTitle("Top 10 Today")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        NavigationLink(value: item) {
                            HStack(alignment: .bottom, spacing: -18) {
                                Text("\(index + 1)")
                                    .font(.system(size: Theme.CardSize.posterHeight * 0.62, weight: .black, design: .rounded))
                                    .foregroundStyle(.black)
                                    .overlay(Text("\(index + 1)").font(.system(size: Theme.CardSize.posterHeight * 0.62, weight: .black, design: .rounded)).strokeText(color: .white.opacity(0.72), width: 1.5))
                                CatalogPosterCard(item: item, scale: 0.82)
                            }
                        }.buttonStyle(NovaListRowStyle()).accessibilityLabel("Number \(index + 1), \(item.title)")
                    }
                }.padding(.horizontal, Theme.Spacing.edge)
            }
        }
    }

    private func posterRow(title: String, items: [CatalogItem]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionTitle(title)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.Spacing.md) {
                    ForEach(items) { item in
                        NavigationLink(value: item) { CatalogPosterCard(item: item, scale: 0.82) }
                            .buttonStyle(NovaListRowStyle())
                    }
                }.padding(.horizontal, Theme.Spacing.edge)
            }
        }
    }

    private func reminderRow(title: String, items: [CatalogItem]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionTitle(title)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Theme.Spacing.md) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            NavigationLink(value: item) { CatalogPosterCard(item: item, scale: 0.82) }
                                .buttonStyle(NovaListRowStyle())
                            Button { reminders.toggle(item); Haptics.selection() } label: {
                                Label(reminders.contains(item) ? "Reminder Set" : "Remind Me",
                                      systemImage: reminders.contains(item) ? "bell.fill" : "bell")
                                    .font(.appFont(14, weight: .bold))
                            }.buttonStyle(NewHotFilterButtonStyle(selected: reminders.contains(item)))
                        }
                    }
                }.padding(.horizontal, Theme.Spacing.edge)
            }
        }
    }

    private func posterGrid(title: String, items: [CatalogItem]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionTitle(title)
            LazyVGrid(columns: Theme.posterGridColumns, spacing: Theme.Spacing.lg) {
                ForEach(items) { item in
                    NavigationLink(value: item) { CatalogPosterCard(item: item, scale: 0.82) }
                        .buttonStyle(NovaListRowStyle())
                }
            }.padding(.horizontal, Theme.Spacing.edge)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(Theme.Font.sectionTitle()).foregroundStyle(.white)
            .padding(.horizontal, Theme.Spacing.edge)
            .accessibilityAddTraits(.isHeader)
    }

    private func filtered(_ items: [CatalogItem]) -> [CatalogItem] {
        switch filter {
        case .movies: return items.filter { $0.contentID.type == .movie }
        case .shows: return items.filter { $0.contentID.type == .series }
        case .all, .reminders: return items
        }
    }

    @MainActor private func load() async {
        guard env.tmdb.hasKey else { loading = false; return }
        loading = true
        errorMessage = nil
        do {
            async let movies = env.tmdb.trendingMovies()
            async let shows = env.tmdb.trendingShows()
            async let currentMovies = env.tmdb.nowPlayingMovies()
            async let currentShows = env.tmdb.airingTodayShows()
            async let upcomingMovies = env.tmdb.upcomingMovies()
            async let upcomingShows = env.tmdb.onTheAirShows()
            async let popularMovies = env.tmdb.popularMovies()
            async let popularShows = env.tmdb.popularShows()
            trending = try await (movies + shows).uniquedCatalog
            newThisWeek = try await (currentMovies + currentShows).uniquedCatalog
            comingSoon = try await (upcomingMovies + upcomingShows).uniquedCatalog
            popular = try await (popularMovies + popularShows).uniquedCatalog
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }
}

@MainActor
private final class CatalogReminderStore: ObservableObject {
    static let shared = CatalogReminderStore()
    @Published private(set) var keys: Set<String>
    private let defaultsKey = "nova.catalog.reminders"
    private init() { keys = Set(UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []) }
    func contains(_ item: CatalogItem) -> Bool { keys.contains(item.id) }
    func toggle(_ item: CatalogItem) {
        if keys.contains(item.id) { keys.remove(item.id) } else { keys.insert(item.id) }
        UserDefaults.standard.set(Array(keys).sorted(), forKey: defaultsKey)
    }
}

private struct NewHotFilterButtonStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.appFont(15, weight: .bold))
            .foregroundStyle(selected ? .white : Theme.Colors.textSecondary)
            .padding(.horizontal, 15).padding(.vertical, 9)
            .background(selected ? Theme.Colors.accent : Theme.Colors.card,
                        in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private extension Array where Element == CatalogItem {
    var uniquedCatalog: [CatalogItem] {
        var seen = Set<String>()
        return filter { seen.insert($0.id).inserted }
    }
}

private extension View {
    func strokeText(color: Color, width: CGFloat) -> some View {
        self.shadow(color: color, radius: 0, x: width, y: 0)
            .shadow(color: color, radius: 0, x: -width, y: 0)
            .shadow(color: color, radius: 0, x: 0, y: width)
            .shadow(color: color, radius: 0, x: 0, y: -width)
    }
}
