//
//  LibraryView.swift
//  Nova
//
//  Streaming-first Library destination with filter segments (All, Favorites, Recently Added,
//  Continue Watching, By Source) and a focusable grid.
//

import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Binding var path: NavigationPath
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var nav: NavigationCoordinator
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var profiles = ViewingProfileStore.shared
    @StateObject private var categoryStore = LibraryCategoryStore.shared
    @State private var filter: LibraryFilter = .recentlyAdded
    @State private var traktCatalog: [CatalogItem] = []
    @State private var traktLoading = false
    @State private var showCollectionPicker = false
    @State private var typeFilter: LibraryTypeFilter = .all
    @State private var hideWatched = false
    @State private var selectedItem: MediaItem?
    @State private var detailItem: MediaItem?
    // Batch B: sort, hidden view, tag filter, bulk edit.
    @State private var sortOrder: LibrarySortOrder = .recentlyAdded
    @State private var showingHidden = false
    @State private var activeTag: String?
    @State private var bulkEditing = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showTagPrompt = false
    @State private var confirmClearContinueWatching = false
    @State private var confirmBulkRemove = false
    @State private var pendingRemovalItem: MediaItem?
    @State private var authenticatedSMBShareIDs: Set<UUID> = []
    @State private var checkingSMBAvailability = false
    @State private var historyHeroIndex = 0
    @State private var trackedWatching: [CatalogItem] = []
    @State private var trackedTVWatchlist: [CatalogItem] = []
    @State private var trackedMovieWatchlist: [CatalogItem] = []
    @State private var trackedCollection: [CatalogItem] = []
    #if os(tvOS)
    @State private var selectedGenre: String?
    @State private var cachedGenres: [String: [String]] = [:]
    #endif

    private var columns: [GridItem] { Theme.posterGridColumns }

    @State private var showStats = false

    /// The poster card used in the main library grid, including the bulk-edit overlay
    /// and context menu. Shared by the iOS UICollectionView grid and the tvOS
    /// LazyVGrid so both paths render identically.
    @ViewBuilder
    private func libraryGridCard(_ item: MediaItem) -> some View {
        MediaCard(item: item,
                  seasonGrouped: true,
                  widthOverride: Theme.isCompact ? 148 : nil,
                  heightOverride: Theme.isCompact ? 178 : nil,
                  artworkScope: .library) {
            if bulkEditing {
                toggleSelection(item.id)
            } else if item.isDirectPlay {
                openDirect(item)
            } else {
                detailItem = item
            }
        }
        .overlay(alignment: .topTrailing) {
            if bulkEditing {
                Image(systemName: selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                    .font(.appFont(24))
                    .foregroundStyle(selectedIDs.contains(item.id) ? Theme.Colors.accent : .white)
                    .padding(8)
                    .shadow(radius: 3)
                    .accessibilityHidden(true)
            }
        }
        .contextMenu {
            if item.hasResumePoint {
                Button(role: .destructive) {
                    withAnimation { library.clearProgress(for: item.id) }
                } label: {
                    Label("Remove from Continue Watching", systemImage: "xmark.circle")
                }
            }
            Button {
                library.toggleFavorite(item)
            } label: {
                Label(item.isFavorite ? "Unfavorite" : "Favorite",
                      systemImage: item.isFavorite ? "star.slash" : "star")
            }
            Button {
                if item.isWatched { library.markUnwatched(item) }
                else { library.markWatched(item) }
            } label: {
                Label(item.isWatched ? "Mark as Unwatched" : "Mark as Watched",
                      systemImage: item.isWatched ? "checkmark.circle.badge.xmark" : "checkmark.circle")
            }
            Button {
                library.toggleHidden(item)
            } label: {
                Label(item.isHidden ? "Unhide" : "Hide", systemImage: item.isHidden ? "eye" : "eye.slash")
            }
            Button(role: .destructive) {
                pendingRemovalItem = item
            } label: {
                Label("Remove from Library", systemImage: "trash")
            }
        }
    }

    /// SMB playback URLs are localhost bridge URLs and do not survive an app or
    /// network restart. Reconnect to the saved share/path before every play.
    private func openDirect(_ item: MediaItem) {
        guard item.sourceType == .smb else {
            selectedItem = item
            return
        }
        Task {
            guard let shareID = item.metadata.smbShareID,
                  let path = item.metadata.smbPath,
                  let share = loadSMBShares().first(where: { $0.id == shareID }) else {
                ToastCenter.shared.show("This SMB item needs a connected library folder. Rescan the folder in Settings.")
                return
            }
            do {
                try await env.smb.connect(to: share)
                let remote = RemoteFileItem(name: URL(fileURLWithPath: path).lastPathComponent,
                                            path: path, isDirectory: false,
                                            size: item.metadata.fileSize, modifiedDate: nil)
                var refreshed = item
                refreshed.playbackURL = try await env.smb.streamURL(for: remote)
                library.update(refreshed)
                selectedItem = refreshed
                NovaQARuntime.shared.record("flow", "My Nova > SMB source refreshed > \(path)")
            } catch {
                authenticatedSMBShareIDs.remove(share.id)
                ToastCenter.shared.show("Couldn't reconnect to \(share.displayName): \(error.localizedDescription)")
                NovaQARuntime.shared.record("error", "My Nova > SMB reconnect failed > \(error.localizedDescription)")
            }
        }
    }

    private func loadSMBShares() -> [SMBShare] {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let data = try? Data(contentsOf: support.appendingPathComponent("smb_shares.json")),
              let shares = try? JSONDecoder().decode([SMBShare].self, from: data) else { return [] }
        return shares
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                #if os(tvOS)
                TVReferenceStyle.canvas.ignoresSafeArea()
                #else
                Theme.Colors.appBackground.ignoresSafeArea()
                if Theme.isCompact {
                    RadialGradient(colors: [
                        Color(red: 0.035, green: 0.16, blue: 0.24).opacity(0.34),
                        Color(red: 0.01, green: 0.035, blue: 0.06).opacity(0.16),
                        .clear
                    ], center: .top, startRadius: 20, endRadius: 620)
                    .ignoresSafeArea()
                }
                #endif

                #if os(tvOS)
                tvLibraryLayout
                #else
                if Theme.isCompact { compactMyNovaFeed } else { wideMyNovaLayout }
                #endif
            }
            .sheet(isPresented: $showStats) {
                NavigationStack { WatchStatsView() }
            }
            .fullScreenCover(item: $selectedItem) { item in
                // Present the player as a full-screen cover so no tab bar, sidebar,
                // or mini-bar remains visible during playback on any platform.
                NavigationStack { PlayerView(item: item) }
            }
            // Present the library item detail as a full navigation push on every
            // platform, matching how Home and Discover open detail. On iPad a plain
            // sheet renders as a small centered form-sheet card, so a push is used
            // instead to fill the screen.
            .navigationDestination(item: $detailItem) { item in
                ContentDetailView(item: item.asCatalogItem())
            }
            .navigationDestination(for: CatalogItem.self) { item in
                ContentDetailView(item: item)
            }
        }
        .onChange(of: nav.pendingContentKey) { _, key in
            openPendingContent(key)
        }
        .onAppear {
            openPendingContent(nav.pendingContentKey)
            loadLibraryPrefs()
            if isTraktTab { filter = .recentlyAdded }
            if let first = displayedItems.first {
                ArtworkHeaderCoordinator.shared.select(first, in: .library)
            }
        }
        .task {
            await refreshSMBAvailability()
            await loadTrackerRails()
        }
        .onReceive(NotificationCenter.default.publisher(for: NetworkConditionMonitor.networkRestored)) { _ in
            Task { await refreshSMBAvailability() }
        }
        .onReceive(CloudSync.shared.externalChange) { changedKeys in
            guard changedKeys.contains("cloud.smbShares") || changedKeys.contains("cloud.libraryFolders") else { return }
            Task { await refreshSMBAvailability() }
        }
        .onChange(of: profiles.activeProfileID) { _, _ in loadLibraryPrefs() }
        .onChange(of: filter) { _, _ in saveLibraryPrefs() }
        .onChange(of: sortOrder) { _, _ in saveLibraryPrefs() }
        .onChange(of: typeFilter) { _, _ in saveLibraryPrefs() }
        .onChange(of: hideWatched) { _, _ in saveLibraryPrefs() }
        .onChange(of: displayedItems) { _, items in
            ImageLoader.shared.prefetch(items.prefix(24).compactMap(\.posterURL), maxPixel: 700)
            if let first = items.first {
                ArtworkHeaderCoordinator.shared.select(first, in: .library)
            }
        }
        .onChange(of: settings.showSMBSeparately) { _, on in
            if !on && filter == .smb { filter = .recentlyAdded }
        }
        .sheet(isPresented: $showCollectionPicker) { CollectionPickerSheet() }
        .alert("Clear Continue Watching?", isPresented: $confirmClearContinueWatching) {
            Button("Clear", role: .destructive) {
                withAnimation { library.clearContinueWatching() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes saved resume points from every visible Continue Watching item.")
        }
        .alert("Remove Selected Items?", isPresented: $confirmBulkRemove) {
            Button("Remove \(selectedIDs.count)", role: .destructive) {
                library.remove(ids: selectedIDs)
                endBulk()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the selected items from your library.")
        }
        .alert("Remove from Library?", isPresented: Binding(
            get: { pendingRemovalItem != nil },
            set: { if !$0 { pendingRemovalItem = nil } }
        )) {
            Button("Remove", role: .destructive) {
                if let item = pendingRemovalItem {
                    withAnimation { library.remove(item) }
                }
                pendingRemovalItem = nil
            }
            Button("Cancel", role: .cancel) {
                pendingRemovalItem = nil
            }
        } message: {
            Text("This item will be removed from your library.")
        }
    }

    #if os(tvOS)
    /// tvOS keeps the library's actual results directly below a single filter row.
    /// The phone/tablet feed and its artwork header remain independent.
    private var tvLibraryLayout: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 42
            let width = max(1, (geometry.size.width - TVReferenceStyle.edge * 2 - spacing * 5) / 6)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    TVPageHeading(title: "Library", systemImage: "books.vertical.fill")
                    Spacer()
                    tvLibraryOptions
                }
                tvLibraryFilters
                ScrollView(.vertical, showsIndicators: false) {
                    if tvDisplayedItems.isEmpty {
                        tvLibraryEmptyState
                            .frame(maxWidth: .infinity, minHeight: 420)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(width), spacing: spacing), count: 6),
                                  alignment: .leading, spacing: 40) {
                            ForEach(tvDisplayedItems, id: \.tvLibraryDisplayID) { item in
                                tvLibraryPoster(item, width: width)
                            }
                        }
                        .padding(.top, 16)
                        .padding(.bottom, 60)
                    }
                }
                .scrollClipDisabled()
            }
            .padding(.horizontal, TVReferenceStyle.edge)
            .padding(.top, TVReferenceStyle.top)
        }
        .ignoresSafeArea()
        .tvRootMenu()
        .toolbar(.hidden, for: .navigationBar)
        .task(id: library.items.map(\.contentKey)) { await loadTVGenres() }
        .onChange(of: detailItem) { _, item in
            if item == nil { Task { await loadTVGenres() } }
        }
        .onChange(of: selectedGenre) { _, genre in
            UserDefaults.standard.set(genre, forKey: libKey("tvGenre"))
        }
        .sheet(isPresented: $showTagPrompt) {
            TextPromptSheet(title: "Add Tag", message: "Tag \(selectedIDs.count) selected items.",
                            placeholder: "Tag name", confirmTitle: "Add") { entered in
                library.addTag(entered, to: selectedIDs)
                endBulk()
            }
        }
    }

    private var tvLibraryFilters: some View {
        HStack(spacing: 20) {
            Menu {
                Button("All Genres") { selectedGenre = nil }
                ForEach(tvAvailableGenres, id: \.self) { genre in
                    Button {
                        selectedGenre = genre
                    } label: {
                        if selectedGenre == genre { Label(genre, systemImage: "checkmark") }
                        else { Text(genre) }
                    }
                }
                if tvAvailableGenres.isEmpty {
                    Text("Open a title's details to make its genres available here.")
                }
            } label: {
                tvFilterLabel(selectedGenre ?? "All Genres")
            }
            .buttonStyle(TVReferenceButtonStyle(selected: selectedGenre != nil))
            .accessibilityLabel("Genre: \(selectedGenre ?? "All Genres")")

            Menu {
                Picker("Type", selection: $typeFilter) {
                    ForEach(LibraryTypeFilter.allCases) { type in
                        Text(type == .all ? "All Types" : type.title).tag(type)
                    }
                }
            } label: {
                tvFilterLabel(typeFilter == .all ? "All Types" : typeFilter.title)
            }
            .buttonStyle(TVReferenceButtonStyle(selected: typeFilter != .all))

            Menu {
                Picker("Sort", selection: $sortOrder) {
                    ForEach(LibrarySortOrder.allCases) { order in
                        Text(order == .recentlyAdded ? "Default" : order.title).tag(order)
                    }
                }
            } label: {
                tvFilterLabel(sortOrder == .recentlyAdded ? "Default" : sortOrder.title)
            }
            .buttonStyle(TVReferenceButtonStyle(selected: sortOrder != .recentlyAdded))

            Text("\(tvDisplayedItems.count) \(tvDisplayedItems.count == 1 ? "item" : "items")")
                .font(.appFont(28))
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize()
                .accessibilityLabel("\(tvDisplayedItems.count) library items")
            Spacer(minLength: 0)
            if bulkEditing {
                Text("\(selectedIDs.count) selected")
                    .font(.appFont(24))
                    .foregroundStyle(.white.opacity(0.8))
            } else if filter != .recentlyAdded || hideWatched || showingHidden || activeTag != nil {
                Text(tvViewDescription)
                    .font(.appFont(24))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }
        }
    }

    private func tvFilterLabel(_ title: String) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.appFont(28, weight: .medium))
            Image(systemName: "chevron.down").font(.appFont(18, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(height: TVReferenceStyle.controlHeight)
        .fixedSize()
    }

    private var tvViewDescription: String {
        var labels: [String] = []
        if filter != .recentlyAdded { labels.append(filterTitle(filter)) }
        if showingHidden { labels.append("Hidden") }
        if hideWatched { labels.append("Unwatched") }
        if let activeTag { labels.append(activeTag) }
        return labels.joined(separator: " · ")
    }

    private var tvLibraryOptions: some View {
        Menu {
            Picker("Library View", selection: $filter) {
                ForEach(activeFilters) { value in
                    Text(value == .recentlyAdded ? "All Library Items" : filterTitle(value)).tag(value)
                }
            }
            Toggle("Hide Watched", isOn: $hideWatched)
            Toggle("Show Hidden Items", isOn: $showingHidden)
            if !library.allTags.isEmpty {
                Menu("Tags") {
                    Button("All Tags") { activeTag = nil }
                    ForEach(library.allTags, id: \.self) { tag in
                        Button(tag) { activeTag = tag }
                    }
                }
            }
            Button("Reset Filters") { resetTVFilters() }
            Divider()
            NavigationLink { CollectionsView() } label: {
                Label("Collections", systemImage: "rectangle.stack")
            }
            NavigationLink { AiringCalendarView() } label: {
                Label("Upcoming Episodes", systemImage: "calendar")
            }
            Button { showStats = true } label: {
                Label("Watch Stats", systemImage: "chart.bar.xaxis")
            }
            Menu("Nova Tracker") {
                NavigationLink("Currently Watching") {
                    tvTrackedTitles("Currently Watching", items: trackedWatching)
                }
                NavigationLink("TV Watchlist") {
                    tvTrackedTitles("TV Watchlist", items: trackedTVWatchlist)
                }
                NavigationLink("Movie Watchlist") {
                    tvTrackedTitles("Movie Watchlist", items: trackedMovieWatchlist)
                }
                NavigationLink("Collection") {
                    tvTrackedTitles("Collection", items: trackedCollection)
                }
            }
            Divider()
            NavigationLink { SMBListView() } label: {
                Label("SMB Shares", systemImage: "externaldrive.connected.to.line.below")
            }
            NavigationLink { LibraryFoldersView() } label: {
                Label("Library Folders", systemImage: "folder")
            }
            Toggle("Show SMB Separately", isOn: $settings.showSMBSeparately)
            NavigationLink { LibraryCategoryManagerView() } label: {
                Label("Edit Library Categories", systemImage: "rectangle.3.group")
            }
            NavigationLink { LibraryEnrichView() } label: {
                Label("Clean Up Library (AI)", systemImage: "wand.and.stars")
            }
            Divider()
            Button(bulkEditing ? "Done Selecting" : "Select Items") {
                if bulkEditing { endBulk() } else { bulkEditing = true }
            }
            if bulkEditing {
                Button(allVisibleSelected ? "Deselect All" : "Select All") { toggleVisibleSelection() }
                Button("Favorite Selected") { library.setFavorite(true, for: selectedIDs); endBulk() }
                    .disabled(selectedIDs.isEmpty)
                Button("Tag Selected") { showTagPrompt = true }.disabled(selectedIDs.isEmpty)
                Button(showingHidden ? "Unhide Selected" : "Hide Selected") {
                    library.setHidden(!showingHidden, for: selectedIDs); endBulk()
                }
                .disabled(selectedIDs.isEmpty)
                Button("Remove Selected", role: .destructive) { confirmBulkRemove = true }
                    .disabled(selectedIDs.isEmpty)
            }
            if filter == .continueWatching && !tvDisplayedItems.isEmpty {
                Button("Clear Continue Watching", role: .destructive) { confirmClearContinueWatching = true }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.appFont(25, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: TVReferenceStyle.controlHeight, height: TVReferenceStyle.controlHeight)
        }
        .buttonStyle(TVReferenceButtonStyle(selected: bulkEditing))
        .accessibilityLabel("Library options")
    }

    private func tvLibraryPoster(_ item: MediaItem, width: CGFloat) -> some View {
        VStack(spacing: 16) {
            Button {
                if bulkEditing { toggleSelection(item.id) }
                else if item.isDirectPlay { openDirect(item) }
                else { detailItem = item }
            } label: {
                tvPosterArtwork(url: item.posterURL, width: width)
                    .overlay(alignment: .topTrailing) {
                        if bulkEditing {
                            Image(systemName: selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                .font(.appFont(32, weight: .semibold))
                                .foregroundStyle(.white)
                                .shadow(color: .black, radius: 5)
                                .padding(14)
                        }
                    }
            }
            .buttonStyle(TVLibraryPosterButtonStyle(selected: bulkEditing && selectedIDs.contains(item.id)))
            .accessibilityLabel(item.seriesTitle ?? item.title)
            .accessibilityHint(bulkEditing ? "Select this title" : (item.isDirectPlay ? "Play this title" : "Open title details"))
            .contextMenu {
                Button(item.isFavorite ? "Unfavorite" : "Favorite") { library.toggleFavorite(item) }
                Button(item.isWatched ? "Mark as Unwatched" : "Mark as Watched") {
                    if item.isWatched { library.markUnwatched(item) } else { library.markWatched(item) }
                }
                Button(item.isHidden ? "Unhide" : "Hide") { library.toggleHidden(item) }
                if item.hasResumePoint {
                    Button("Remove from Continue Watching", role: .destructive) { library.clearProgress(for: item.id) }
                }
                Button("Remove from Library", role: .destructive) { pendingRemovalItem = item }
            }
            Text(item.seriesTitle ?? item.title)
                .font(.appFont(24, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: width, height: 32)
                .accessibilityHidden(true)
        }
        .frame(width: width)
    }

    private func tvPosterArtwork(url: URL?, width: CGFloat) -> some View {
        CachedAsyncImage(url: url, maxPixel: 800) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            ZStack {
                Theme.Colors.card
                Image(systemName: "film")
                    .font(.appFont(44, weight: .light))
                    .foregroundStyle(.white.opacity(0.2))
            }
        }
        .frame(width: width, height: width * 1.5)
        .clipShape(RoundedRectangle(cornerRadius: TVReferenceStyle.cornerRadius, style: .continuous))
    }

    private func tvTrackedTitles(_ title: String, items: [CatalogItem]) -> some View {
        GeometryReader { geometry in
            let width = max(1, (geometry.size.width - TVReferenceStyle.edge * 2 - 42 * 5) / 6)
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    Text(title).font(.appFont(36, weight: .semibold)).foregroundStyle(.white)
                    if items.isEmpty {
                        Text("No titles here yet.").font(.appFont(28)).foregroundStyle(.white.opacity(0.7))
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(width), spacing: 42), count: 6), spacing: 40) {
                        ForEach(items) { item in
                            VStack(spacing: 16) {
                                NavigationLink(value: item) { tvPosterArtwork(url: item.posterURL, width: width) }
                                    .buttonStyle(TVLibraryPosterButtonStyle())
                                    .accessibilityLabel(item.title)
                                Text(item.title).font(.appFont(24, weight: .medium)).foregroundStyle(.white)
                                    .lineLimit(1).frame(width: width, height: 32).accessibilityHidden(true)
                            }
                        }
                    }
                }
                .padding(.horizontal, TVReferenceStyle.edge)
                .padding(.vertical, TVReferenceStyle.top)
            }
            .scrollClipDisabled()
        }
        .background(TVReferenceStyle.canvas.ignoresSafeArea())
    }

    private var tvDisplayedItems: [MediaItem] {
        let items = displayedItems.filter { item in
            guard let selectedGenre else { return true }
            return tvGenres(for: item).contains { $0.caseInsensitiveCompare(selectedGenre) == .orderedSame }
        }
        // A deterministic tie break keeps equal-year/date rows from jumping while
        // artwork and remote metadata arrive.
        return items.sorted { left, right in
            switch sortOrder {
            case .recentlyAdded:
                if left.addedDate != right.addedDate { return left.addedDate > right.addedDate }
            case .title:
                let comparison = (left.seriesTitle ?? left.title).localizedCaseInsensitiveCompare(right.seriesTitle ?? right.title)
                if comparison != .orderedSame { return comparison == .orderedAscending }
            case .year:
                let leftYear = left.metadata.year ?? 0
                let rightYear = right.metadata.year ?? 0
                if leftYear != rightYear { return leftYear > rightYear }
            case .recentlyPlayed:
                let leftDate = left.lastPlayedDate ?? .distantPast
                let rightDate = right.lastPlayedDate ?? .distantPast
                if leftDate != rightDate { return leftDate > rightDate }
            }
            return left.tvLibraryDisplayID < right.tvLibraryDisplayID
        }
    }

    private var tvAvailableGenres: [String] {
        var names: [String: String] = [:]
        for item in displayedItems {
            for genre in tvGenres(for: item) {
                let name = genre.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { names[name.lowercased()] = name }
            }
        }
        return names.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func tvGenres(for item: MediaItem) -> [String] {
        guard let key = item.contentID?.stableKey else { return [] }
        return (cachedGenres[key] ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// Reuse existing local metadata: genre filtering never fans out remote detail
    /// requests merely because the user opened a large library.
    private func loadTVGenres() async {
        let keys = Set(library.items.compactMap { $0.contentID?.stableKey }.filter { !$0.hasPrefix("unknown:") })
        var index: [String: [String]] = [:]
        for key in keys {
            guard !Task.isCancelled else { return }
            if let cached = await CatalogCaches.metadata.staleValue(for: key), !cached.genres.isEmpty {
                index[key] = cached.genres
            } else if let cached = await OfflineMetadataCache.shared.item(for: key) {
                index[key] = cached.genres
            }
        }
        guard !Task.isCancelled else { return }
        for item in trackedWatching + trackedTVWatchlist + trackedMovieWatchlist + trackedCollection where !item.genres.isEmpty {
            index[item.id] = item.genres
        }
        cachedGenres = index
    }

    private var tvLibraryEmptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "books.vertical").font(.appFont(50, weight: .light))
            Text(tvHasFilters ? "No matching titles" : "Your library is empty")
                .font(.appFont(32, weight: .semibold))
            Text(tvHasFilters ? "Try another filter to see more of your library." : "Add a source or discover a title to get started.")
                .font(.appFont(24)).foregroundStyle(.white.opacity(0.65))
            Button {
                if tvHasFilters { resetTVFilters() } else { nav.selection = .settings }
            } label: {
                Text(tvHasFilters ? "Reset Filters" : "Set Up Sources")
                    .font(.appFont(26, weight: .medium))
                    .padding(.horizontal, 24)
                    .frame(height: TVReferenceStyle.controlHeight)
            }
            .padding(.top, 8)
            .buttonStyle(TVReferenceButtonStyle())
        }
        .foregroundStyle(.white)
    }

    private var tvHasFilters: Bool {
        selectedGenre != nil || typeFilter != .all || filter != .recentlyAdded || showingHidden || hideWatched || activeTag != nil
    }

    private func resetTVFilters() {
        selectedGenre = nil
        typeFilter = .all
        filter = .recentlyAdded
        showingHidden = false
        hideWatched = false
        activeTag = nil
    }
    #endif

    /// One Netflix-style feed on iPhone. The hero, shortcuts, tracking rails, and
    /// Recently Added grid share this ScrollView, so the grid never behaves like a
    /// second independently scrolling page.
    private var compactMyNovaFeed: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.md) {
                cleanHeader
                libraryQuickActions
                trackerRails
                libraryResultsContent(useReusableGrid: false)
            }
            .padding(.bottom, Theme.Spacing.xl)
        }
        .ignoresSafeArea(edges: .top)
    }

    private var wideMyNovaLayout: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            cleanHeader
            libraryQuickActions
            trackerRails
            libraryResultsContent(useReusableGrid: true)
        }
    }

    @ViewBuilder
    private func libraryResultsContent(useReusableGrid: Bool) -> some View {
        if !displayedItems.isEmpty { librarySectionHeader }
        if isTraktTab {
            traktGrid
        } else if displayedItems.isEmpty {
            EmptyStateView(systemImage: emptyIcon, title: emptyTitle, message: emptyMessage,
                           actionTitle: emptyActionTitle, actionSystemImage: emptyActionSystemImage,
                           action: emptyAction)
        } else if useReusableGrid {
            #if os(iOS)
            PosterCollectionGrid(items: displayedItems,
                                 minItemWidth: Theme.CardSize.posterWidth * 0.90,
                                 spacing: Theme.Spacing.lg,
                                 sectionInsets: EdgeInsets(top: Theme.Spacing.md, leading: Theme.Spacing.edge,
                                                           bottom: Theme.Spacing.md, trailing: Theme.Spacing.edge),
                                 reloadToken: AnyHashable("\(bulkEditing)|\(selectedIDs.hashValue)"),
                                 prefetchURL: { $0.posterURL }) { item in
                libraryGridContent(item)
            }
            #else
            swiftUIGrid
            #endif
        } else {
            swiftUIGrid
        }
    }

    private var swiftUIGrid: some View {
        LazyVGrid(columns: columns, spacing: Theme.Spacing.lg) {
            ForEach(displayedItems) { item in libraryGridCard(item) }
        }
        .padding(.horizontal, Theme.Spacing.edge)
        .padding(.vertical, Theme.Spacing.xs)
    }

    private func libraryThumbnailURL(_ item: MediaItem) -> URL? { item.posterURL }
    private func libraryGridContent(_ item: MediaItem) -> some View {
        libraryGridCard(item).environmentObject(library)
    }

    @ViewBuilder
    private var trackerRails: some View {
        if !trackedWatching.isEmpty || !trackedTVWatchlist.isEmpty || !trackedMovieWatchlist.isEmpty || !trackedCollection.isEmpty {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                trackerRail("Currently Watching", items: trackedWatching)
                trackerRail("TV Watchlist", items: trackedTVWatchlist)
                trackerRail("Movie Watchlist", items: trackedMovieWatchlist)
                trackerRail("Collection", items: trackedCollection)
            }
            .padding(.vertical, Theme.Spacing.xs)
        }
    }

    @ViewBuilder
    private func trackerRail(_ title: String, items: [CatalogItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(title)
                    .font(Theme.Font.sectionTitle())
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.horizontal, Theme.Spacing.edge)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: Theme.Spacing.md) {
                        ForEach(items) { item in
                            NavigationLink(value: item) {
                                VStack(alignment: .leading, spacing: 6) {
                                    CachedAsyncImage(url: item.posterURL, maxPixel: 600) { image in
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } placeholder: { Theme.Colors.card }
                                    .frame(width: Theme.isCompact ? 116 : 150, height: Theme.isCompact ? 174 : 225)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    Text(item.title).font(.appFont(13, weight: .medium))
                                        .foregroundStyle(Theme.Colors.textPrimary).lineLimit(1)
                                }
                                .frame(width: Theme.isCompact ? 116 : 150, alignment: .leading)
                            }
                            .buttonStyle(NovaListRowStyle())
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.edge)
                }
            }
        }
    }

    private func loadTrackerRails() async {
        async let watching = env.novaTracker.statusItems("watching")
        async let watchlist = env.trackers.watchlist()
        async let collection = env.novaTracker.libraryItems("collected")
        let loaded = await (watching, watchlist, collection)
        async let enrichedWatching = env.tmdb.enrichArtwork(loaded.0)
        async let enrichedWatchlist = env.tmdb.enrichArtwork(loaded.1)
        async let enrichedCollection = env.tmdb.enrichArtwork(loaded.2)
        let enriched = await (enrichedWatching, enrichedWatchlist, enrichedCollection)
        trackedWatching = enriched.0
        trackedTVWatchlist = enriched.1.filter { $0.contentID.type == .series }
        trackedMovieWatchlist = enriched.1.filter { $0.contentID.type == .movie }
        trackedCollection = enriched.2
        #if os(tvOS)
        for item in enriched.0 + enriched.1 + enriched.2 where !item.genres.isEmpty {
            cachedGenres[item.id] = item.genres
        }
        #endif
    }

    /// Opens the library item matching a deep-link content key, then clears the
    /// pending key so it doesn't re-fire.
    private func openPendingContent(_ key: String?) {
        guard let key, !key.isEmpty else { return }
        if let match = library.items.first(where: { $0.contentKey == key || $0.contentID?.stableKey == key }) {
            detailItem = match
        }
        nav.pendingContentKey = nil
    }

    // MARK: - Headers (clean vs classic)

    /// The original header: title, inline sort/edit/collections icons, tag row, bulk
    /// bar, and the stacked filter chips.
    @ViewBuilder
    private var classicHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Library")
                .font(Theme.Font.screenTitle())
                .screenTitleStyle()
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            Menu {
                Picker("Sort", selection: $sortOrder) {
                    ForEach(LibrarySortOrder.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down.circle")
                    .font(.appFont(20))
                    .foregroundStyle(Theme.Colors.accent)
            }
            Button {
                bulkEditing.toggle()
                if !bulkEditing { selectedIDs.removeAll() }
            } label: {
                Image(systemName: bulkEditing ? "checkmark.circle.fill" : "checklist")
                    .font(.appFont(20))
                    .foregroundStyle(Theme.Colors.accent)
            }
            Button { showCollectionPicker = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.stack")
                    Text("Collections")
                }
                .font(.appFont(18, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent)
            }
            .novaRowStyle()
        }
        .padding(.horizontal, Theme.Spacing.edge)
        .padding(.top, Theme.Spacing.lg)

        if !library.allTags.isEmpty {
            tagFilterRow
        }
        if bulkEditing {
            bulkBar
        }

        HStack {
            filterBar
            Spacer()
            if filter == .continueWatching && !displayedItems.isEmpty {
                Button {
                    confirmClearContinueWatching = true
                } label: {
                    Text("Clear All")
                        .font(.appFont(17, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                }
                .novaRowStyle()
                .padding(.trailing, Theme.Spacing.edge)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Mockup 1's canonical composition with one consolidated options menu. Filters,
    /// sorting, collections, and editing no longer consume two persistent rows.
    @ViewBuilder
    private var cleanHeader: some View {
        let heroes = library.viewingHistoryHeroItems
        ZStack(alignment: .top) {
            if !heroes.isEmpty {
                let item = heroes[min(historyHeroIndex, heroes.count - 1)]
                historyHeroArtwork(item)
                    .id(item.contentKey)
                    .transition(.opacity)
            } else {
                LinearGradient(colors: [Theme.Colors.backgroundElevated, Theme.Colors.background],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }

            LinearGradient(colors: [
                Theme.Colors.background.opacity(0.12),
                .clear,
                Theme.Colors.background.opacity(0.28),
                Theme.Colors.background
            ], startPoint: .top, endPoint: .bottom)

            HStack(spacing: 9) {
                Text("Library")
                .font(.appFont(Theme.isCompact ? 32 : 54, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer(minLength: 8)

                optionsMenu
            }
            .padding(.horizontal, Theme.Spacing.edge)
            .padding(.top, Theme.isCompact ? 68 : 30)
        }
        // Reach behind the status bar and retain enough vertical room to show the
        // complete selected artwork. The backdrop itself uses aspect-fit over a
        // blurred full-bleed copy, so this never widens or distorts a poster.
        .frame(height: Theme.isCompact ? 300 : 320)
        .clipShape(RoundedRectangle(cornerRadius: Theme.isCompact ? 32 : 34, style: .continuous))
        .padding(.horizontal, Theme.isCompact ? 8 : Theme.Spacing.edge)
        .animation(profiles.preferences.reduceArtworkMotion ? nil : Theme.Motion.crossfade,
                   value: historyHeroIndex)
        .task(id: heroes.map(\.contentKey)) {
            historyHeroIndex = min(historyHeroIndex, max(heroes.count - 1, 0))
            guard heroes.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(12))
                guard !Task.isCancelled else { return }
                withAnimation(Theme.Motion.crossfade) {
                    historyHeroIndex = (historyHeroIndex + 1) % heroes.count
                }
            }
        }

        if !library.allTags.isEmpty {
            tagFilterRow
        }
        if bulkEditing {
            bulkBar
        }
    }

    @ViewBuilder
    private func historyHeroArtwork(_ item: MediaItem) -> some View {
        if let url = item.backdropURL ?? item.posterURL {
            CachedAsyncImage(url: url, maxPixel: 1600) { image in
                ZStack {
                    image.resizable().aspectRatio(contentMode: .fill)
                        .blur(radius: 20).scaleEffect(1.08)
                    image.resizable().aspectRatio(contentMode: .fit)
                }
            } placeholder: {
                Theme.Colors.backgroundElevated
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .accessibilityLabel("Recently watched: \(item.displayTitle)")
        } else {
            LinearGradient(colors: [Theme.Colors.cardElevated, Theme.Colors.background],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .accessibilityLabel("Recently watched: \(item.displayTitle)")
        }
    }

    /// The consolidated options menu behind the sliders icon in the clean header.
    private var optionsMenu: some View {
        Menu {
            Button {
                showStats = true
            } label: {
                Label("Your Watch Stats", systemImage: "chart.bar.xaxis")
            }
            Divider()
            Picker("View", selection: $filter) {
                ForEach(activeFilters) { f in
                    Label(filterTitle(f), systemImage: filterIcon(f)).tag(f)
                }
            }
            Picker("Media Type", selection: $typeFilter) {
                ForEach(LibraryTypeFilter.allCases) { target in
                    Text(target.title).tag(target)
                }
            }
            Picker("Sort", selection: $sortOrder) {
                ForEach(LibrarySortOrder.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
            }
            Toggle(isOn: $hideWatched) {
                Label("Hide Watched", systemImage: "checkmark.circle.badge.xmark")
            }
            Toggle(isOn: $settings.showSMBSeparately) {
                Label("Show SMB Separately", systemImage: "externaldrive.connected.to.line.below")
            }
            NavigationLink { MediaServersView() } label: {
                Label("Media Servers", systemImage: "play.tv")
            }
            NavigationLink { LibraryEnrichView() } label: {
                Label("Clean Up Library (AI)", systemImage: "wand.and.stars")
            }
            NavigationLink { LibraryCategoryManagerView() } label: {
                Label("Edit Library Categories", systemImage: "rectangle.3.group")
            }
            Divider()
            Button {
                bulkEditing.toggle()
                if !bulkEditing { selectedIDs.removeAll() }
            } label: {
                Label(bulkEditing ? "Done Editing" : "Select Items",
                      systemImage: bulkEditing ? "checkmark.circle.fill" : "checklist")
            }
            Button {
                showCollectionPicker = true
            } label: {
                Label("Collections", systemImage: "rectangle.stack")
            }
            if filter == .continueWatching && !displayedItems.isEmpty {
                Button(role: .destructive) {
                    confirmClearContinueWatching = true
                } label: {
                    Label("Clear Continue Watching", systemImage: "xmark.circle")
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.appFont(16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75))
        }
        .novaIconStyle()
        .accessibilityLabel("Library options")
    }

    private var libraryStatusRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Label(librarySummaryText, systemImage: "line.3.horizontal.decrease.circle")
                .font(.appFont(14, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            if activeTag != nil || hideWatched || showingHidden || typeFilter != .all {
                Button("Reset Filters") {
                    activeTag = nil
                    hideWatched = false
                    showingHidden = false
                    typeFilter = .all
                }
                .font(.appFont(14, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Spacing.edge)
        .padding(.top, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    /// Keeps secondary destinations discoverable without stacking several full-width
    /// rows above the library. The horizontal layout remains calm on iPhone and grows
    /// naturally on iPad/tvOS.
    @ViewBuilder
    private var libraryQuickActions: some View {
        if Theme.isCompact {
            HStack(spacing: Theme.Spacing.sm) {
                NavigationLink { CollectionsView() } label: {
                    libraryQuickAction(title: "Collections",
                                       detail: "\(library.collections.count)",
                                       systemImage: "rectangle.stack")
                }
                NavigationLink { AiringCalendarView() } label: {
                    libraryQuickAction(title: "Upcoming",
                                       detail: "Episodes",
                                       systemImage: "calendar")
                }
                #if os(iOS)
                NavigationLink { OfflineDownloadsView() } label: {
                    libraryQuickAction(title: "Downloads",
                                       detail: "\(env.downloads.downloads.count)",
                                       systemImage: "arrow.down.circle")
                }
                #endif
            }
            .padding(.horizontal, Theme.Spacing.edge)
            .padding(.top, 2)
            .padding(.bottom, 4)
            .buttonStyle(.plain)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    NavigationLink { CollectionsView() } label: {
                        libraryQuickAction(title: "Collections", detail: "\(library.collections.count)", systemImage: "rectangle.stack")
                    }
                    NavigationLink { AiringCalendarView() } label: {
                        libraryQuickAction(title: "Upcoming", detail: "Episodes", systemImage: "calendar")
                    }
                    #if os(iOS)
                    NavigationLink { OfflineDownloadsView() } label: {
                        libraryQuickAction(title: "Downloads", detail: "\(env.downloads.downloads.count)", systemImage: "arrow.down.circle")
                    }
                    #endif
                    Button { showStats = true } label: {
                        libraryQuickAction(title: "Watch Stats", detail: "Progress", systemImage: "chart.bar.xaxis")
                    }
                }
                .padding(.horizontal, Theme.Spacing.edge)
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
        }
    }

    private func libraryQuickAction(title: String, detail: String, systemImage: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.appFont(15, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 30, height: 30)
                .background(Theme.Colors.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.appFont(Theme.isCompact ? 12 : 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(detail)
                    .font(.appFont(Theme.isCompact ? 11 : 12))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .frame(minWidth: Theme.isCompact ? 0 : 132,
               maxWidth: Theme.isCompact ? .infinity : nil,
               minHeight: Theme.isCompact ? 42 : Theme.minTouchTarget,
               alignment: .leading)
        .padding(.horizontal, Theme.isCompact ? 7 : Theme.Spacing.sm)
        .cinematicGlass(radius: Theme.isCompact ? 11 : 14)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var librarySectionHeader: some View {
        HStack {
            Text(filterTitle(filter))
                .font(.appFont(19, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            if !Theme.isCompact {
                Text("\(displayedItems.count) items")
                    .font(.appFont(13, weight: .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(.horizontal, Theme.isCompact ? 20 : Theme.Spacing.edge)
        .padding(.top, Theme.isCompact ? 8 : 6)
    }

    private var librarySummaryText: String {
        let count = displayedItems.count
        let itemWord = count == 1 ? "item" : "items"
        if checkingSMBAvailability && filter == .smb {
            return "Checking connected SMB folders…"
        }
        if isTraktTab {
            return traktLoading ? "Loading \(filterTitle(filter))" : "\(traktCatalog.count) Trakt \(traktCatalog.count == 1 ? "item" : "items")"
        }
        if let activeTag {
            return "\(count) \(itemWord) tagged \(activeTag)"
        }
        if showingHidden {
            return "\(count) hidden \(itemWord)"
        }
        if hideWatched {
            return "\(count) unwatched \(itemWord)"
        }
        return "\(count) \(itemWord)"
    }

    private func filterIcon(_ f: LibraryFilter) -> String {
        switch f {
        case .recentlyAdded:    return "clock"
        case .favorites:        return "star"
        case .continueWatching: return "play.circle"
        case .smb:              return "externaldrive.connected.to.line.below"
        case .mediaServers:     return "play.tv"
        case .traktWatchlist:   return "text.badge.star"
        case .traktTrending:    return "flame"
        case .collection:       return "rectangle.stack"
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(activeFilters) { f in
                        FocusableButton(title: f.title, prominent: f == filter) {
                            filter = f
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.edge)
            }
            // Movie / show type filter, applied on top of the active filter.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(LibraryTypeFilter.allCases) { t in
                        FocusableButton(title: t.title, systemImage: t.systemImage,
                                        prominent: t == typeFilter) {
                            typeFilter = t
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.edge)
            }
        }
        .padding(.vertical, Theme.Spacing.sm)
    }

    // MARK: - Data

    private var activeFilters: [LibraryFilter] {
        var f = categoryStore.visibleFilters
        if settings.showSMBSeparately && !authenticatedSMBShareIDs.isEmpty { f.append(.smb) }
        if !env.mediaServers.connections.isEmpty { f.append(.mediaServers) }
        for idString in settings.pinnedCollections {
            if let id = UUID(uuidString: idString),
               library.collections.contains(where: { $0.id == id }) {
                f.append(.collection(id))
            }
        }
        return f
    }

    private func filterTitle(_ f: LibraryFilter) -> String {
        if case .collection(let id) = f,
           let c = library.collections.first(where: { $0.id == id }) { return c.name }
        return categoryStore.title(for: f)
    }

    private var isTraktTab: Bool { filter == .traktWatchlist || filter == .traktTrending }

    // MARK: - Per-profile filter persistence
    /// Library sort/filter/type/hide-watched are remembered independently for each
    /// viewing profile, so switching profiles restores that profile's view.
    private func libKey(_ field: String) -> String {
        "library.\(profiles.activeProfileID.uuidString).\(field)"
    }

    private func loadLibraryPrefs() {
        let d = UserDefaults.standard
        if let raw = d.string(forKey: libKey("sort")), let s = LibrarySortOrder(rawValue: raw) { sortOrder = s }
        if let fi = d.object(forKey: libKey("filter")) as? Int, LibraryFilter.allCases.indices.contains(fi) {
            filter = LibraryFilter.allCases[fi]
        }
        if let ti = d.object(forKey: libKey("type")) as? Int, LibraryTypeFilter.allCases.indices.contains(ti) {
            typeFilter = LibraryTypeFilter.allCases[ti]
        }
        hideWatched = d.bool(forKey: libKey("hideWatched"))
        #if os(tvOS)
        selectedGenre = d.string(forKey: libKey("tvGenre"))
        #endif
    }

    private func saveLibraryPrefs() {
        let d = UserDefaults.standard
        d.set(sortOrder.rawValue, forKey: libKey("sort"))
        if let fi = LibraryFilter.allCases.firstIndex(of: filter) { d.set(fi, forKey: libKey("filter")) }
        if let ti = LibraryTypeFilter.allCases.firstIndex(of: typeFilter) { d.set(ti, forKey: libKey("type")) }
        d.set(hideWatched, forKey: libKey("hideWatched"))
    }

    private func loadTraktIfNeeded() async {
        guard isTraktTab else { return }
        traktLoading = true
        defer { traktLoading = false }
        let raw: [CatalogItem]
        if filter == .traktWatchlist {
            raw = await env.trackers.watchlist()
        } else {
            raw = await env.trackers.trendingShows()
        }
        traktCatalog = await env.tmdb.enrichArtwork(raw)
    }

    @ViewBuilder private var traktGrid: some View {
        if traktLoading && traktCatalog.isEmpty {
            SkeletonGrid(columns: columns)
        } else if traktCatalog.isEmpty {
            EmptyStateView(systemImage: "text.badge.star",
                           title: "Nothing here yet",
                           message: "Connect Trakt in Settings and add titles to see them here.")
        } else {
            LazyVGrid(columns: columns, spacing: Theme.Spacing.lg) {
                ForEach(traktCatalog) { item in
                    NavigationLink(value: item) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            CachedAsyncImage(url: item.posterURL, maxPixel: 700) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                    .fill(Theme.Colors.card)
                            }
                            .aspectRatio(2.0 / 3.0, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                            Text(item.title)
                                .font(.appFont(15, weight: .medium))
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(NovaListRowStyle())
                }
            }
            .padding(.horizontal, Theme.Spacing.edge)
            .padding(.vertical, Theme.Spacing.md)
        }
    }

    private var displayedItems: [MediaItem] {
        var base: [MediaItem]
        switch filter {
        case .recentlyAdded:     base = library.libraryEntries
        case .favorites:         base = library.favorites
        case .continueWatching:  base = library.continueWatching
        case .smb:               base = library.libraryEntries.filter { $0.sourceType == .smb }
        case .mediaServers:      base = library.libraryEntries.filter { $0.metadata.mediaServerID != nil }
        case .traktWatchlist, .traktTrending:
            base = []   // Trakt tabs render their own catalog grid
        case .collection(let id):
            if let c = library.collections.first(where: { $0.id == id }) {
                base = library.items(in: c)
            } else { base = [] }
        }
        // SMB records remain safely stored, but are only surfaced while their saved
        // share has just connected/authenticated and its configured folder exists.
        // This prevents stale network entries from cluttering My Nova after a share
        // is removed, signed out, or goes offline.
        base = base.filter { item in
            guard item.sourceType == .smb else { return true }
            guard let shareID = item.metadata.smbShareID else { return false }
            return authenticatedSMBShareIDs.contains(shareID)
        }
        if settings.showSMBSeparately && filter != .smb {
            base = base.filter { $0.sourceType != .smb }
        }
        var result: [MediaItem]
        switch typeFilter {
        case .all:    result = base
        #if os(tvOS)
        case .shows:  result = base.filter(\.isSeries)
        case .movies: result = base.filter { !$0.isSeries && $0.sourceType != .liveTV }
        #else
        case .shows:  result = base.filter { $0.episode != nil || $0.seriesTitle != nil }
        case .movies: result = base.filter { $0.episode == nil && $0.seriesTitle == nil }
        #endif
        }
        // Hide hidden/archived items unless the user is viewing them.
        result = result.filter { showingHidden ? $0.isHidden : !$0.isHidden }
        // Optionally hide fully-watched titles.
        if hideWatched {
            result = result.filter { !$0.isWatched }
        }
        // Tag filter, when one is selected.
        if let tag = activeTag {
            result = result.filter { $0.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } }
        }
        // Collections, favorites, source filters, and the main library all use the
        // same one-card-per-series rule. The chosen card is the latest watched
        // episode, never a separate card for every episode.
        return sortItems(library.collapseToShow(result))
    }

    /// Revalidates each configured SMB source using the same authenticated connect
    /// path as playback. When library folders are configured, at least one folder on
    /// the share must also be listable before its items become visible.
    private func refreshSMBAvailability() async {
        guard !checkingSMBAvailability else { return }
        checkingSMBAvailability = true
        defer { checkingSMBAvailability = false }

        let shares = loadSMBShares()
        let folders = env.libraryFolders.folders
        var verified: Set<UUID> = []

        for share in shares {
            guard !Task.isCancelled else { return }
            do {
                try await env.smb.connect(to: share)
                let configuredFolders = folders.filter { $0.shareID == share.id }
                if configuredFolders.isEmpty {
                    verified.insert(share.id)
                } else {
                    var foundReachableFolder = false
                    for folder in configuredFolders where !foundReachableFolder {
                        let path = folder.path.isEmpty ? "/" : folder.path
                        if (try? await env.smb.listDirectory(path)) != nil {
                            foundReachableFolder = true
                        }
                    }
                    if foundReachableFolder { verified.insert(share.id) }
                }
            } catch {
                NovaLog.network.notice("Hiding unavailable SMB share \(share.displayName, privacy: .public) from My Nova")
            }
        }

        authenticatedSMBShareIDs = verified
        if filter == .smb && verified.isEmpty {
            filter = .recentlyAdded
        }
    }

    /// Applies the active sort order.
    private func sortItems(_ items: [MediaItem]) -> [MediaItem] {
        switch sortOrder {
        case .recentlyAdded:
            return items.sorted { $0.addedDate > $1.addedDate }
        case .title:
            return items.sorted { ($0.seriesTitle ?? $0.title).localizedCaseInsensitiveCompare($1.seriesTitle ?? $1.title) == .orderedAscending }
        case .year:
            return items.sorted { ($0.metadata.year ?? 0) > ($1.metadata.year ?? 0) }
        case .recentlyPlayed:
            return items.sorted { ($0.lastPlayedDate ?? .distantPast) > ($1.lastPlayedDate ?? .distantPast) }
        }
    }

    // MARK: - Batch B views

    private var tagFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                tagChip(title: "All", active: activeTag == nil) { activeTag = nil }
                ForEach(library.allTags, id: \.self) { tag in
                    tagChip(title: tag, active: activeTag?.caseInsensitiveCompare(tag) == .orderedSame) {
                        activeTag = (activeTag?.caseInsensitiveCompare(tag) == .orderedSame) ? nil : tag
                    }
                }
                // Toggle showing hidden/archived items.
                tagChip(title: showingHidden ? "Hidden Items" : "Show Hidden",
                        active: showingHidden,
                        systemImage: "eye.slash") { showingHidden.toggle() }
            }
            .padding(.horizontal, Theme.Spacing.edge)
        }
    }

    private func tagChip(title: String, active: Bool, systemImage: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.appFont(15, weight: .medium))
            .foregroundStyle(active ? Theme.Colors.background : Theme.Colors.textSecondary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(active ? Theme.Colors.accent : Theme.Colors.card, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(NovaChipButtonStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }

    private var bulkBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("\(selectedIDs.count) selected")
                .font(.appFont(15, weight: .semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            Button(allVisibleSelected ? "Deselect" : "Select All") {
                toggleVisibleSelection()
            }
            .font(.appFont(12, weight: .semibold))
            .foregroundStyle(Theme.Colors.accent)
            .buttonStyle(.plain)
            .disabled(displayedItems.isEmpty)
            bulkAction("star", "Favorite") { library.setFavorite(true, for: selectedIDs); endBulk() }
            bulkAction("tag", "Tag") { showTagPrompt = true }
            bulkAction("eye.slash", "Hide") { library.setHidden(!showingHidden, for: selectedIDs); endBulk() }
            bulkAction("trash", "Remove", destructive: true) { confirmBulkRemove = true }
        }
        .padding(.horizontal, Theme.Spacing.edge)
        .padding(.vertical, Theme.Spacing.sm)
        .sheet(isPresented: $showTagPrompt) {
            TextPromptSheet(title: "Add Tag",
                             message: "Tag \(selectedIDs.count) selected items.",
                             placeholder: "Tag name",
                             confirmTitle: "Add") { entered in
                library.addTag(entered, to: selectedIDs)
                endBulk()
            }
        }
        .background(.thinMaterial)
    }

    private func bulkAction(_ icon: String, _ label: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                Text(label).font(.appFont(11))
            }
            .foregroundStyle(destructive ? Theme.Colors.error : Theme.Colors.accent)
            .padding(.horizontal, Theme.Spacing.sm)
            .frame(minWidth: Theme.minTouchTarget, minHeight: Theme.minTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(selectedIDs.isEmpty)
        .opacity(selectedIDs.isEmpty ? 0.4 : 1)
        .accessibilityLabel(label)
    }

    private func endBulk() {
        selectedIDs.removeAll()
        bulkEditing = false
    }

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    private var visibleIDs: Set<UUID> {
        #if os(tvOS)
        Set(tvDisplayedItems.map(\.id))
        #else
        Set(displayedItems.map(\.id))
        #endif
    }

    private var allVisibleSelected: Bool {
        !visibleIDs.isEmpty && visibleIDs.isSubset(of: selectedIDs)
    }

    private func toggleVisibleSelection() {
        if allVisibleSelected {
            selectedIDs.subtract(visibleIDs)
        } else {
            selectedIDs.formUnion(visibleIDs)
        }
    }

    private var emptyMessage: String {
        if showingHidden { return "Hidden titles appear here after you hide them from the main library." }
        if activeTag != nil { return "No titles match this tag with the current filters." }
        if hideWatched { return "Everything in this view is already watched, or nothing matches the current filters." }
        switch filter {
        case .favorites:        return "Tap the star on any title to keep it close."
        case .continueWatching: return "Start watching something and it'll show up here."
        default:                return "Add a source or discover something to get started."
        }
    }

    private var emptyTitle: String {
        if showingHidden { return "No hidden items" }
        if activeTag != nil { return "No tagged items" }
        switch filter {
        case .favorites:        return "No favorites yet"
        case .continueWatching: return "Nothing in progress"
        default:                return "Your library is empty"
        }
    }

    private var emptyIcon: String {
        if showingHidden { return "eye.slash" }
        if activeTag != nil { return "tag" }
        switch filter {
        case .favorites:        return "star"
        case .continueWatching: return "play.circle"
        default:                return "rectangle.stack"
        }
    }

    private var emptyActionTitle: String? {
        if showingHidden || activeTag != nil || hideWatched { return "Reset Filters" }
        switch filter {
        case .favorites:        return nil
        case .continueWatching: return "Discover"
        default:                return "Set Up Sources"
        }
    }

    private var emptyActionSystemImage: String? {
        if showingHidden || activeTag != nil || hideWatched { return "line.3.horizontal.decrease.circle" }
        switch filter {
        case .continueWatching: return "magnifyingglass"
        case .favorites:        return nil
        default:                return "gearshape"
        }
    }

    private func emptyAction() {
        if showingHidden || activeTag != nil || hideWatched {
            showingHidden = false
            activeTag = nil
            hideWatched = false
            typeFilter = .all
            return
        }
        switch filter {
        case .continueWatching: nav.selection = .discover
        case .favorites:        break
        default:                nav.selection = .settings
        }
    }
}

#if os(tvOS)
private extension MediaItem {
    /// A series keeps its focus identity when another episode becomes its card.
    var tvLibraryDisplayID: String {
        if isSeries {
            return "series:" + (seriesTitle?.lowercased() ?? contentID?.stableKey ?? title.lowercased())
        }
        return id.uuidString
    }
}

/// Focus belongs to the poster, preserving both the image colors and row geometry.
private struct TVLibraryPosterButtonStyle: ButtonStyle {
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        PosterBody(configuration: configuration, selected: selected)
    }

    private struct PosterBody: View {
        let configuration: Configuration
        let selected: Bool
        @Environment(\.isFocused) private var focused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .overlay {
                    RoundedRectangle(cornerRadius: TVReferenceStyle.cornerRadius, style: .continuous)
                        .strokeBorder(focused ? .white : selected ? Theme.Colors.accent : .clear,
                                      lineWidth: focused ? 4 : 3)
                }
                .shadow(color: .black.opacity(focused ? 0.65 : 0.15), radius: focused ? 14 : 4, y: 5)
                .opacity(configuration.isPressed ? 0.85 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: focused)
        }
    }
}
#endif

// MARK: - Filters

/// Filters the library by content type, applied on top of the section filter.
enum LibrarySortOrder: String, Hashable, Identifiable, CaseIterable {
    case recentlyAdded, title, year, recentlyPlayed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .recentlyAdded:  return "Recently Added"
        case .title:          return "Title"
        case .year:           return "Year"
        case .recentlyPlayed: return "Recently Played"
        }
    }
    var systemImage: String {
        switch self {
        case .recentlyAdded:  return "clock"
        case .title:          return "textformat"
        case .year:           return "calendar"
        case .recentlyPlayed: return "play"
        }
    }
}

enum LibraryTypeFilter: Hashable, Identifiable, CaseIterable {
    case all, movies, shows

    var id: String {
        switch self {
        case .all:    return "all"
        case .movies: return "movies"
        case .shows:  return "shows"
        }
    }

    var title: String {
        switch self {
        case .all:    return "All"
        case .movies: return "Movies"
        case .shows:  return "Shows"
        }
    }

    var systemImage: String {
        switch self {
        case .all:    return "square.grid.2x2"
        case .movies: return "film"
        case .shows:  return "tv"
        }
    }
}

private struct LibraryCategoryPreference: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var isEnabled: Bool
}

@MainActor
private final class LibraryCategoryStore: ObservableObject {
    static let shared = LibraryCategoryStore()
    @Published var categories: [LibraryCategoryPreference] { didSet { persist() } }
    private let key = "nova.library.categories.v1"

    private static let defaults = [
        LibraryCategoryPreference(id: "recent", title: "Recently Added", isEnabled: true),
        LibraryCategoryPreference(id: "fav", title: "Favorites", isEnabled: true),
        LibraryCategoryPreference(id: "continue", title: "Continue Watching", isEnabled: true),
    ]

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([LibraryCategoryPreference].self, from: data),
           !saved.isEmpty {
            categories = saved
        } else {
            categories = Self.defaults
        }
    }

    var visibleFilters: [LibraryFilter] {
        let filters = categories.filter(\.isEnabled).compactMap { LibraryFilter(stableID: $0.id) }
        return filters.isEmpty ? [.recentlyAdded] : filters
    }

    func title(for filter: LibraryFilter) -> String {
        categories.first(where: { $0.id == filter.id })?.title ?? filter.title
    }

    func remove(at offsets: IndexSet) {
        categories.remove(atOffsets: offsets)
        if categories.isEmpty { categories = Self.defaults }
    }

    func move(from offsets: IndexSet, to destination: Int) {
        categories.move(fromOffsets: offsets, toOffset: destination)
    }

    func restoreDefaults() { categories = Self.defaults }

    func importJSON(from url: URL) throws {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        let decoded = try JSONDecoder().decode([LibraryCategoryPreference].self, from: Data(contentsOf: url))
        let allowed = Set(Self.defaults.map(\.id))
        let sanitized = decoded
            .filter { allowed.contains($0.id) }
            .reduce(into: [LibraryCategoryPreference]()) { result, entry in
                guard !result.contains(where: { $0.id == entry.id }) else { return }
                var clean = entry
                clean.title = String(entry.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
                if clean.title.isEmpty { clean.title = LibraryFilter(stableID: entry.id)?.title ?? "Category" }
                result.append(clean)
            }
        guard !sanitized.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        categories = sanitized
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(categories) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

private struct LibraryCategoryManagerView: View {
    @StateObject private var store = LibraryCategoryStore.shared
    @State private var importing = false
    @State private var importError: String?

    @ViewBuilder
    var body: some View {
        #if os(tvOS)
        categoryList
            .listStyle(.plain)
            .background(TVReferenceStyle.canvas.ignoresSafeArea())
            .preferredColorScheme(.dark)
        #else
        categoryList
            .toolbar { EditButton() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do { try store.importJSON(from: result.get()) }
                catch { importError = error.localizedDescription }
            }
        #endif
    }

    private var categoryList: some View {
        List {
            Section {
                ForEach($store.categories) { $category in
                    HStack(spacing: 12) {
                        Toggle("", isOn: $category.isEnabled).labelsHidden()
                        TextField("Category name", text: $category.title)
                    }
                }
                .onDelete(perform: store.remove)
                .onMove(perform: store.move)
            } header: {
                Text("Library categories")
            } footer: {
                Text("Rename, hide, reorder, or remove the default Library categories. At least one usable category is always retained.")
            }

            Section {
                #if !os(tvOS)
                Button { importing = true } label: {
                    Label("Import Categories JSON", systemImage: "square.and.arrow.down")
                }
                #endif
                Button("Restore Defaults", role: .destructive) { store.restoreDefaults() }
            }
        }
        .navigationTitle("Library Categories")
        .alert("Couldn't Import Categories", isPresented: Binding(
            get: { importError != nil }, set: { if !$0 { importError = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(importError ?? "Unknown error") }
    }
}

enum LibraryFilter: Hashable, Identifiable, CaseIterable {
    case recentlyAdded
    case favorites
    case continueWatching
    case smb
    case mediaServers
    case traktWatchlist
    case traktTrending
    case collection(UUID)

    static var allCases: [LibraryFilter] {
        [.recentlyAdded, .favorites, .continueWatching]
    }

    var id: String {
        switch self {
        case .recentlyAdded:      return "recent"
        case .favorites:          return "fav"
        case .continueWatching:   return "continue"
        case .smb:                return "smb"
        case .mediaServers:       return "media-servers"
        case .traktWatchlist:     return "trakt-watchlist"
        case .traktTrending:      return "trakt-trending"
        case .collection(let id): return "collection-\(id.uuidString)"
        }
    }

    init?(stableID: String) {
        switch stableID {
        case "recent": self = .recentlyAdded
        case "fav": self = .favorites
        case "continue": self = .continueWatching
        case "smb": self = .smb
        case "media-servers": self = .mediaServers
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .recentlyAdded:     return "Recently Added"
        case .favorites:         return "Favorites"
        case .continueWatching:  return "Continue Watching"
        case .smb:               return "Network (SMB)"
        case .mediaServers:      return "Media Servers"
        case .traktWatchlist:    return "Trakt Watchlist"
        case .traktTrending:     return "Trakt Trending"
        case .collection:        return "Collection"
        }
    }
}
