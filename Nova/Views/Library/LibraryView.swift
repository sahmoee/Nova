//
//  LibraryView.swift
//  Nova
//
//  Unified library with filter segments (All, Favorites, Recently Added,
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
                Theme.Colors.appBackground.ignoresSafeArea()
                if Theme.isCompact {
                    RadialGradient(colors: [
                        Color(red: 0.035, green: 0.16, blue: 0.24).opacity(0.34),
                        Color(red: 0.01, green: 0.035, blue: 0.06).opacity(0.16),
                        .clear
                    ], center: .top, startRadius: 20, endRadius: 620)
                    .ignoresSafeArea()
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    // My Nova now has one canonical presentation.  Do not allow an
                    // older synced `classic` preference to silently restore the
                    // superseded layout on another device.
                    cleanHeader

                    libraryQuickActions

                    if !displayedItems.isEmpty {
                        librarySectionHeader
                    }

                    if isTraktTab {
                        ScrollView { traktGrid }
                    } else if displayedItems.isEmpty {
                        EmptyStateView(
                            systemImage: emptyIcon,
                            title: emptyTitle,
                            message: emptyMessage,
                            actionTitle: emptyActionTitle,
                            actionSystemImage: emptyActionSystemImage,
                            action: emptyAction
                        )
                    } else {
                        #if os(iOS)
                        // UICollectionView-backed grid: real cell reuse + poster
                        // prefetching for smooth scrolling on large libraries. Cards
                        // are the same SwiftUI views, hosted per cell; `library` must
                        // be re-injected because UIHostingConfiguration does not
                        // inherit environment objects. `reloadToken` re-runs the card
                        // builder when bulk-edit state changes without the item set.
                        PosterCollectionGrid(
                            items: displayedItems,
                            minItemWidth: Theme.isCompact ? 148 : Theme.CardSize.posterWidth * 0.90,
                            spacing: Theme.isCompact ? 22 : Theme.Spacing.lg,
                            sectionInsets: EdgeInsets(top: Theme.isCompact ? 4 : Theme.Spacing.md,
                                                      leading: Theme.isCompact ? 35 : Theme.Spacing.edge,
                                                      bottom: Theme.Spacing.md,
                                                      trailing: Theme.isCompact ? 35 : Theme.Spacing.edge),
                            reloadToken: AnyHashable("\(bulkEditing)|\(selectedIDs.hashValue)"),
                            prefetchURL: { $0.posterURL }
                        ) { item in
                            libraryGridCard(item)
                                .environmentObject(library)
                        }
                        #else
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: Theme.Spacing.lg) {
                                ForEach(displayedItems) { item in
                                    libraryGridCard(item)
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.edge)
                            .padding(.vertical, Theme.Spacing.md)
                        }
                        #endif
                    }
                }
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
            ImageLoader.shared.prefetch(items.compactMap(\.posterURL), maxPixel: 700)
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
            Text("My Nova")
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
        ZStack(alignment: .top) {
            Image("MyNovaHero")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(maxWidth: .infinity, alignment: .center)
                .clipped()

            LinearGradient(colors: [
                Theme.Colors.background.opacity(0.12),
                .clear,
                Theme.Colors.background.opacity(0.28),
                Theme.Colors.background
            ], startPoint: .top, endPoint: .bottom)

            HStack(spacing: 9) {
                Text("My Nova")
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
        .frame(height: Theme.isCompact ? 320 : 380)
        .padding(.top, Theme.isCompact ? -60 : 0)

        if !library.allTags.isEmpty {
            tagFilterRow
        }
        if bulkEditing {
            bulkBar
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
        case .shows:  result = base.filter { $0.episode != nil || $0.seriesTitle != nil }
        case .movies: result = base.filter { $0.episode == nil && $0.seriesTitle == nil }
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
        Set(displayedItems.map(\.id))
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
                Text("Rename, hide, reorder, or remove the default My Nova categories. At least one usable category is always retained.")
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
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .recentlyAdded:     return "Recently Added"
        case .favorites:         return "Favorites"
        case .continueWatching:  return "Continue Watching"
        case .smb:               return "Network (SMB)"
        case .traktWatchlist:    return "Trakt Watchlist"
        case .traktTrending:     return "Trakt Trending"
        case .collection:        return "Collection"
        }
    }
}
