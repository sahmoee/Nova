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
    @State private var filter: LibraryFilter = .recentlyAdded
    @State private var typeFilter: LibraryTypeFilter = .all
    @State private var selectedItem: MediaItem?
    @State private var detailItem: MediaItem?

    private let columns = [GridItem(.adaptive(minimum: Theme.CardSize.posterWidth),
                                    spacing: Theme.Spacing.md)]

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()

                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Text("Library")
                        .font(Theme.Font.screenTitle())
                        .screenTitleStyle()
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .padding(.horizontal, Theme.Spacing.edge)
                        .padding(.top, Theme.Spacing.lg)

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
                                        detailItem = item
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
            .sheet(item: $detailItem) { item in
                MediaDetailView(item: item) {
                    detailItem = nil
                    selectedItem = item
                }
            }
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
        switch typeFilter {
        case .all:    return base
        case .shows:  return base.filter { $0.episode != nil || $0.seriesTitle != nil }
        case .movies: return base.filter { $0.episode == nil && $0.seriesTitle == nil }
        }
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
