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
    @State private var browsing = true
    @State private var prompt = ""
    @State private var catalogResults: [CatalogItem] = []
    @State private var libraryResults: [MediaItem] = []
    @State private var state: ViewState = .idle
    @State private var lastPrompt = ""
    @State private var playerItem: MediaItem?
    @FocusState private var promptFocused: Bool

    enum ViewState: Equatable { case idle, working, results, empty, error(String) }

    private var columns: [GridItem] { Theme.posterGridColumns }

    private var featureColumns: [GridItem] {
        [GridItem(.adaptive(minimum: Theme.isCompact ? 160 : 240),
                  spacing: Theme.Spacing.md)]
    }

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
                        if browsing {
                            header
                            if !AISearchService.isConfigured {
                                setupBanner
                            }
                            featureMenu
                        } else {
                            activeFeatureHeader
                            promptField
                            suggestionChips
                            resultsSection
                        }
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

    /// Shown once a feature is chosen: the feature's name plus a way back to the menu.
    private var activeFeatureHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Button {
                browsing = true
                resetResults()
            } label: {
                Label("All AI Features", systemImage: "chevron.left")
                    .font(.appFont(16, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
            }
            .buttonStyle(NovaChipButtonStyle())

            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: capability.systemImage)
                    .font(.appFont(30, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(capability.rawValue)
                        .font(Theme.Font.sectionTitle())
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(capability.blurb)
                        .font(.appFont(16))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
    }

    // MARK: - Feature menu

    /// The browsable directory of every AI capability, grouped so features read as a
    /// well-organized list instead of an endless row of chips.
    private var featureMenu: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            // Jump back into the last-used feature without hunting through groups.
            if let raw = UserDefaults.standard.string(forKey: PrefKey.aiLastFeature),
               let recent = AISearchService.Capability(rawValue: raw) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Label("Jump Back In", systemImage: "clock.arrow.circlepath")
                        .font(.appFont(21, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    LazyVGrid(columns: featureColumns, spacing: Theme.Spacing.md) {
                        Button {
                            select(recent)
                        } label: {
                            featureCard(recent)
                        }
                        .buttonStyle(NovaChipButtonStyle())
                    }
                }
            }
            ForEach(AISearchService.Capability.Category.allCases) { category in
                let caps = AISearchService.Capability.allCases.filter { $0.category == category }
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Label(category.rawValue, systemImage: category.systemImage)
                        .font(.appFont(21, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    LazyVGrid(columns: featureColumns, spacing: Theme.Spacing.md) {
                        ForEach(caps) { cap in
                            Button {
                                select(cap)
                            } label: {
                                featureCard(cap)
                            }
                            .buttonStyle(NovaChipButtonStyle())
                        }
                    }
                }
            }
        }
    }

    private func featureCard(_ cap: AISearchService.Capability) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Image(systemName: cap.systemImage)
                .font(.appFont(26, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent)
                .frame(height: 32)
            Text(cap.rawValue)
                .font(.appFont(18, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(cap.blurb)
                .font(.appFont(14))
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.card,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func select(_ cap: AISearchService.Capability) {
        capability = cap
        UserDefaults.standard.set(cap.rawValue, forKey: PrefKey.aiLastFeature)
        resetResults()
        browsing = false
        // Surprise Me needs no prompt at all — run it immediately.
        if cap == .surpriseMe {
            run()
        } else {
            promptFocused = true
        }
    }

    // MARK: - Prompt input

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
                if !capability.searchesLibrary {
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
        catalogResults = []; libraryResults = []; state = .idle; lastPrompt = ""
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
