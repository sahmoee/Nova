//
//  LibraryView.swift
//  FrameTV
//
//  Unified library with filter segments (All, Favorites, Recently Added,
//  Continue Watching, By Source) and a focusable grid.
//

import SwiftUI

struct LibraryView: View {
    @Binding var path: NavigationPath
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var nav: NavigationCoordinator
    @EnvironmentObject private var settings: SettingsStore
    @State private var filter: LibraryFilter = .recentlyAdded
    @State private var typeFilter: LibraryTypeFilter = .all
    @AppStorage("library.hideWatched") private var hideWatched = false
    @State private var selectedItem: MediaItem?
    @State private var detailItem: MediaItem?
    // Batch B: sort, hidden view, tag filter, bulk edit.
    @State private var sortOrder: LibrarySortOrder = .recentlyAdded
    @State private var showingHidden = false
    @State private var activeTag: String?
    @State private var bulkEditing = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showTagPrompt = false
    @State private var newTagText = ""

    private var columns: [GridItem] { Theme.posterGridColumns }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.Colors.appBackground.ignoresSafeArea()

                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    switch settings.libraryStyle {
                    case .clean:   cleanHeader
                    case .classic: classicHeader
                    }

                    if displayedItems.isEmpty {
                        EmptyStateView(
                            systemImage: emptyIcon,
                            title: emptyTitle,
                            message: emptyMessage,
                            actionTitle: emptyActionTitle,
                            action: emptyAction
                        )
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: Theme.Spacing.lg) {
                                ForEach(displayedItems) { item in
                                    MediaCard(item: item, seasonGrouped: true) {
                                        if bulkEditing {
                                            toggleSelection(item.id)
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
                                            withAnimation { library.remove(item) }
                                        } label: {
                                            Label("Remove from Library", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.edge)
                            .padding(.vertical, Theme.Spacing.md)
                        }
                    }
                }
            }
            .navigationDestination(item: $selectedItem) { item in
                PlayerView(item: item)
            }
            #if os(tvOS)
            // tvOS sheets render as a hard-to-see partial card with unreliable focus,
            // so present the library item detail as a full navigation push instead.
            // Play pushes the player on top (don't pop detail first — popping and
            // pushing at once in one stack conflicts); backing out returns to detail.
            .navigationDestination(item: $detailItem) { item in
                ContentDetailView(item: item.asCatalogItem())
            }
            #else
            .sheet(item: $detailItem) { item in
                NavigationStack {
                    ContentDetailView(item: item.asCatalogItem())
                }
            }
            #endif
        }
        .onChange(of: nav.pendingContentKey) { _, key in
            openPendingContent(key)
        }
        .onAppear { openPendingContent(nav.pendingContentKey) }
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
            NavigationLink {
                CollectionsView()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.stack")
                    Text("Collections")
                }
                .font(.appFont(18, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent)
            }
            .frameRowStyle()
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
                    withAnimation { library.clearContinueWatching() }
                } label: {
                    Text("Clear All")
                        .font(.appFont(17, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                }
                .frameRowStyle()
                .padding(.trailing, Theme.Spacing.edge)
            }
        }
    }

    /// The new default header: a large title, a single options button (sort,
    /// collections, edit, hidden), and a prominent All/Movies/Shows segmented control.
    @ViewBuilder
    private var cleanHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("My Library")
                .font(Theme.Font.screenTitle())
                .screenTitleStyle()
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            optionsMenu
        }
        .padding(.horizontal, Theme.Spacing.edge)
        .padding(.top, Theme.Spacing.lg)

        // Segmented All / Movies / Shows control.
        Picker("Type", selection: $typeFilter) {
            ForEach(LibraryTypeFilter.allCases) { t in
                Text(t.title).tag(t)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Theme.Spacing.edge)
        .padding(.top, Theme.Spacing.xs)

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
            Picker("View", selection: $filter) {
                ForEach(LibraryFilter.allCases) { f in
                    Label(f.title, systemImage: filterIcon(f)).tag(f)
                }
            }
            Picker("Sort", selection: $sortOrder) {
                ForEach(LibrarySortOrder.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
            }
            Toggle(isOn: $hideWatched) {
                Label("Hide Watched", systemImage: "checkmark.circle.badge.xmark")
            }
            Divider()
            Button {
                bulkEditing.toggle()
                if !bulkEditing { selectedIDs.removeAll() }
            } label: {
                Label(bulkEditing ? "Done Editing" : "Select Items",
                      systemImage: bulkEditing ? "checkmark.circle.fill" : "checklist")
            }
            NavigationLink {
                CollectionsView()
            } label: {
                Label("Collections", systemImage: "rectangle.stack")
            }
            if filter == .continueWatching && !displayedItems.isEmpty {
                Button(role: .destructive) {
                    withAnimation { library.clearContinueWatching() }
                } label: {
                    Label("Clear Continue Watching", systemImage: "xmark.circle")
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.appFont(22, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(Theme.Spacing.sm)
                .background(Theme.Colors.card, in: Circle())
        }
        .frameIconStyle()
    }

    private func filterIcon(_ f: LibraryFilter) -> String {
        switch f {
        case .recentlyAdded:    return "clock"
        case .favorites:        return "star"
        case .continueWatching: return "play.circle"
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(LibraryFilter.allCases) { f in
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

    private var displayedItems: [MediaItem] {
        let base: [MediaItem]
        switch filter {
        case .recentlyAdded:     base = library.libraryEntries
        case .favorites:         base = library.favorites
        case .continueWatching:  base = library.continueWatching
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
        return sortItems(result)
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
                tagChip(title: showingHidden ? "Hiding Shown" : "Show Hidden",
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
        .buttonStyle(.plain)
    }

    private var bulkBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("\(selectedIDs.count) selected")
                .font(.appFont(15, weight: .semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            bulkAction("star", "Favorite") { library.setFavorite(true, for: selectedIDs); endBulk() }
            bulkAction("tag", "Tag") { showTagPrompt = true }
            bulkAction("eye.slash", "Hide") { library.setHidden(!showingHidden, for: selectedIDs); endBulk() }
            bulkAction("trash", "Remove", destructive: true) { library.remove(ids: selectedIDs); endBulk() }
        }
        .padding(.horizontal, Theme.Spacing.edge)
        .padding(.vertical, Theme.Spacing.sm)
        .alert("Add Tag", isPresented: $showTagPrompt) {
            TextField("Tag name", text: $newTagText)
            Button("Cancel", role: .cancel) { newTagText = "" }
            Button("Add") {
                library.addTag(newTagText, to: selectedIDs)
                newTagText = ""; endBulk()
            }
        } message: {
            Text("Tag \(selectedIDs.count) selected items.")
        }
    }

    private func bulkAction(_ icon: String, _ label: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                Text(label).font(.appFont(11))
            }
            .foregroundStyle(destructive ? Theme.Colors.error : Theme.Colors.accent)
            .padding(.horizontal, Theme.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(selectedIDs.isEmpty)
        .opacity(selectedIDs.isEmpty ? 0.4 : 1)
    }

    private func endBulk() {
        selectedIDs.removeAll()
        bulkEditing = false
    }

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    private var emptyMessage: String {
        switch filter {
        case .favorites:        return "Tap the star on any title to keep it close."
        case .continueWatching: return "Start watching something and it'll show up here."
        default:                return "Add a source or discover something to get started."
        }
    }

    private var emptyTitle: String {
        switch filter {
        case .favorites:        return "No favorites yet"
        case .continueWatching: return "Nothing in progress"
        default:                return "Your library is empty"
        }
    }

    private var emptyIcon: String {
        switch filter {
        case .favorites:        return "star"
        case .continueWatching: return "play.circle"
        default:                return "rectangle.stack"
        }
    }

    private var emptyActionTitle: String? {
        switch filter {
        case .favorites:        return nil
        case .continueWatching: return "Discover"
        default:                return "Set Up Sources"
        }
    }

    private func emptyAction() {
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

enum LibraryFilter: Hashable, Identifiable, CaseIterable {
    case recentlyAdded
    case favorites
    case continueWatching

    static var allCases: [LibraryFilter] {
        [.recentlyAdded, .favorites, .continueWatching]
    }

    var id: String {
        switch self {
        case .recentlyAdded:     return "recent"
        case .favorites:         return "fav"
        case .continueWatching:  return "continue"
        }
    }

    var title: String {
        switch self {
        case .recentlyAdded:     return "Recently Added"
        case .favorites:         return "Favorites"
        case .continueWatching:  return "Continue Watching"
        }
    }
}
