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
    @State private var filter: LibraryFilter = .all
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

                    filterBar

                    if displayedItems.isEmpty {
                        EmptyStateView(
                            systemImage: "rectangle.stack",
                            title: "Nothing here yet",
                            message: emptyMessage
                        )
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: Theme.Spacing.lg) {
                                ForEach(displayedItems) { item in
                                    MediaCard(item: item) {
                                        detailItem = item
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(LibraryFilter.allCases) { f in
                    FocusableButton(title: f.title, prominent: f == filter) {
                        filter = f
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.edge)
            .padding(.vertical, Theme.Spacing.sm)
        }
    }

    // MARK: - Data

    private var displayedItems: [MediaItem] {
        switch filter {
        case .all:               return library.recentlyAdded
        case .favorites:         return library.favorites
        case .recentlyAdded:     return library.recentlyAdded
        case .continueWatching:  return library.continueWatching
        case .source(let type):  return library.items(for: type)
        }
    }

    private var emptyMessage: String {
        switch filter {
        case .favorites:        return "Mark items as favorites to see them here."
        case .continueWatching: return "Start watching something and it'll show up here."
        default:                return "Add media from the Sources tab to get started."
        }
    }
}

// MARK: - Filter

enum LibraryFilter: Hashable, Identifiable, CaseIterable {
    case all
    case favorites
    case recentlyAdded
    case continueWatching
    case source(SourceType)

    static var allCases: [LibraryFilter] {
        [.all, .favorites, .recentlyAdded, .continueWatching]
        + SourceType.allCases.map { .source($0) }
    }

    var id: String {
        switch self {
        case .all:               return "all"
        case .favorites:         return "fav"
        case .recentlyAdded:     return "recent"
        case .continueWatching:  return "continue"
        case .source(let t):     return "src.\(t.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .all:               return "All"
        case .favorites:         return "Favorites"
        case .recentlyAdded:     return "Recently Added"
        case .continueWatching:  return "Continue Watching"
        case .source(let t):     return t.displayName
        }
    }
}
