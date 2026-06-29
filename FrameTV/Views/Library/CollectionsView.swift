//
//  CollectionsView.swift
//  FrameTV
//
//  Lists the user's collections (intent-based folders of library items) and lets them
//  create new ones. Tapping a collection shows its items; an item can be played from
//  there. Collections are managed in LibraryStore and synced via iCloud.
//

import SwiftUI

struct CollectionsView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var showingNewCollection = false
    @State private var newName = ""
    @State private var selectedItem: MediaItem?

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: Theme.isCompact ? 160 : 260), spacing: Theme.Spacing.lg)]
    }

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    header

                    if library.collections.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(columns: columns, spacing: Theme.Spacing.lg) {
                            ForEach(library.collections) { collection in
                                NavigationLink {
                                    CollectionDetailView(collection: collection,
                                                         onPlay: { selectedItem = $0 })
                                } label: {
                                    collectionTile(collection)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.edge)
                    }
                }
                .padding(.bottom, Theme.Spacing.xl)
            }
        }
        .navigationTitle("Collections")
        .navigationDestination(item: $selectedItem) { item in
            PlayerView(item: item)
        }
        .toolbar {
            Button { showingNewCollection = true } label: {
                Image(systemName: "plus")
            }
        }
        .alert("New Collection", isPresented: $showingNewCollection) {
            TextField("Name", text: $newName)
            Button("Create") {
                let trimmed = newName.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { library.createCollection(name: trimmed) }
                newName = ""
            }
            Button("Cancel", role: .cancel) { newName = "" }
        } message: {
            Text("Name your collection, like Halloween or Comfort Shows.")
        }
    }

    private var header: some View {
        Text("Collections")
            .font(Theme.Font.screenTitle())
            .screenTitleStyle()
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.horizontal, Theme.Spacing.edge)
            .padding(.top, Theme.Spacing.lg)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.appFont(56))
                .foregroundStyle(Theme.Colors.textTertiary)
            Text("No collections yet")
                .font(.appFont(24, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Create collections to organize titles by intent — like Halloween, Comfort Shows, or one just for the kids.")
                .font(.appFont(18))
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            FocusableButton(title: "New Collection", systemImage: "plus", prominent: true) {
                showingNewCollection = true
            }
            .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.xl)
    }

    private func collectionTile(_ collection: MediaCollection) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.Colors.card)
                    .aspectRatio(1.6, contentMode: .fit)
                Image(systemName: collection.systemImage)
                    .font(.appFont(44, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
            }
            Text(collection.name)
                .font(.appFont(20, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
            Text("\(collection.count) \(collection.count == 1 ? "title" : "titles")")
                .font(.appFont(15))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .contextMenu {
            Button(role: .destructive) {
                library.deleteCollection(collection.id)
            } label: {
                Label("Delete Collection", systemImage: "trash")
            }
        }
    }
}

/// Shows the items inside a single collection.
struct CollectionDetailView: View {
    let collection: MediaCollection
    var onPlay: (MediaItem) -> Void
    @EnvironmentObject private var library: LibraryStore

    private var columns: [GridItem] {
        Theme.posterGridColumns
    }

    private var items: [MediaItem] {
        // Re-read from the store so removals reflect immediately.
        let current = library.collections.first(where: { $0.id == collection.id }) ?? collection
        return library.items(in: current)
    }

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()
            ScrollView {
                if items.isEmpty {
                    VStack(spacing: Theme.Spacing.md) {
                        Image(systemName: collection.systemImage)
                            .font(.appFont(52))
                            .foregroundStyle(Theme.Colors.textTertiary)
                        Text("This collection is empty")
                            .font(.appFont(22, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("Add titles to it from a movie or show's menu.")
                            .font(.appFont(18))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, Theme.Spacing.xl)
                } else {
                    LazyVGrid(columns: columns, spacing: Theme.Spacing.lg) {
                        ForEach(items) { item in
                            MediaCard(item: item) { onPlay(item) }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        library.removeFromCollection(collection.id, contentKey: item.contentKey)
                                    } label: {
                                        Label("Remove from Collection", systemImage: "minus.circle")
                                    }
                                }
                        }
                    }
                    .padding(Theme.Spacing.edge)
                }
            }
        }
        .navigationTitle(collection.name)
    }
}
