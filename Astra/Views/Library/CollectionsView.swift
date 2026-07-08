//
//  CollectionsView.swift
//  Astra
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
    @State private var editing = false
    @State private var pendingDelete: MediaCollection?

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: Theme.isCompact ? 160 : 260), spacing: Theme.Spacing.lg)]
    }

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    header

                    // Smart Collections: auto-updating groups based on simple rules.
                    smartSection

                    if library.collections.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(columns: columns, spacing: Theme.Spacing.lg) {
                            ForEach(library.collections) { collection in
                                if editing {
                                    // Edit mode: tiles stop navigating and grow a
                                    // delete badge, so removing collections is a
                                    // visible one-tap action rather than a hidden
                                    // long-press.
                                    collectionTile(collection)
                                        .overlay(alignment: .topTrailing) {
                                            deleteBadge(for: collection)
                                        }
                                } else {
                                    NavigationLink {
                                        CollectionDetailView(collection: collection,
                                                             onPlay: { selectedItem = $0 })
                                    } label: {
                                        collectionTile(collection)
                                    }
                                    .buttonStyle(.plain)
                                }
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
            if !library.collections.isEmpty {
                Button(editing ? "Done" : "Edit") {
                    withAnimation { editing.toggle() }
                }
            }
            Button { showingNewCollection = true } label: {
                Image(systemName: "plus")
            }
        }
        .alert("Delete Collection?",
               isPresented: Binding(get: { pendingDelete != nil },
                                    set: { if !$0 { pendingDelete = nil } }),
               presenting: pendingDelete) { collection in
            Button("Delete “\(collection.name)”", role: .destructive) {
                library.deleteCollection(collection.id)
                Haptics.play(.success)
                pendingDelete = nil
                if library.collections.isEmpty { editing = false }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { collection in
            Text("“\(collection.name)” will be deleted. Its titles stay in your library.")
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
                // A montage of up to four posters from the collection's contents;
                // empty collections keep the symbol placeholder.
                let posters = montagePosters(for: collection)
                if posters.isEmpty {
                    Image(systemName: collection.systemImage)
                        .font(.appFont(44, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                } else {
                    montage(posters)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card,
                                                    style: .continuous))
                }
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
                pendingDelete = collection
            } label: {
                Label("Delete Collection", systemImage: "trash")
            }
        }
    }

    /// Poster URLs for a collection's montage tile (up to four).
    private func montagePosters(for collection: MediaCollection) -> [URL] {
        Array(library.items(in: collection).compactMap(\.posterURL).prefix(4))
    }

    /// A 2x2 (or fewer) grid of posters filling the tile.
    private func montage(_ urls: [URL]) -> some View {
        GeometryReader { geo in
            let cols = urls.count >= 2 ? 2 : 1
            let rows = urls.count >= 3 ? 2 : 1
            let w = geo.size.width / CGFloat(cols)
            let h = geo.size.height / CGFloat(rows)
            VStack(spacing: 1) {
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: 1) {
                        ForEach(0..<cols, id: \.self) { c in
                            let idx = r * cols + c
                            if idx < urls.count {
                                CachedAsyncImage(url: urls[idx], maxPixel: 400) { image in
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Rectangle().fill(Theme.Colors.card)
                                }
                                .frame(width: w, height: h)
                                .clipped()
                            } else {
                                Rectangle().fill(Theme.Colors.card)
                                    .frame(width: w, height: h)
                            }
                        }
                    }
                }
            }
        }
        .aspectRatio(1.6, contentMode: .fit)
    }

    /// The red delete button shown on each tile while editing. Deletion always
    /// confirms first, so a stray tap can't wipe a collection.
    private func deleteBadge(for collection: MediaCollection) -> some View {
        Button {
            pendingDelete = collection
        } label: {
            Image(systemName: "trash.circle.fill")
                .font(.appFont(32))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .red)
                .shadow(color: .black.opacity(0.4), radius: 4)
        }
        .buttonStyle(.plain)
        .padding(Theme.Spacing.xs)
        .accessibilityLabel("Delete \(collection.name)")
    }

    // MARK: - Smart collections

    @ViewBuilder private var smartSection: some View {
        let smarts = SmartCollection.presets.filter { !$0.items(from: library.items).isEmpty }
        if !smarts.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Smart Collections")
                    .font(.appFont(22, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.horizontal, Theme.Spacing.edge)
                LazyVGrid(columns: columns, spacing: Theme.Spacing.lg) {
                    ForEach(smarts) { smart in
                        NavigationLink {
                            SmartCollectionDetailView(smart: smart, onPlay: { selectedItem = $0 })
                        } label: {
                            smartTile(smart, count: smart.items(from: library.items).count)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.Spacing.edge)
            }
        }
    }

    private func smartTile(_ smart: SmartCollection, count: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.Colors.cardGradient)
                    .aspectRatio(1.6, contentMode: .fit)
                Image(systemName: smart.systemImage)
                    .font(.appFont(44, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
            }
            Text(smart.name)
                .font(.appFont(20, weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
            Text("\(count) \(count == 1 ? "title" : "titles")")
                .font(.appFont(15))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
    }
}

/// Shows the items inside a single collection.
struct CollectionDetailView: View {
    let collection: MediaCollection
    var onPlay: (MediaItem) -> Void
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false

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
            Theme.Colors.appBackground.ignoresSafeArea()
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
        .toolbar {
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Image(systemName: "trash")
            }
        }
        .alert("Delete Collection?", isPresented: $confirmingDelete) {
            Button("Delete “\(collection.name)”", role: .destructive) {
                library.deleteCollection(collection.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("“\(collection.name)” will be deleted. Its titles stay in your library.")
        }
    }
}

// MARK: - Smart collection detail

/// Shows the live contents of a smart collection, re-evaluated from the library each
/// time it appears so it always reflects the current state.
struct SmartCollectionDetailView: View {
    let smart: SmartCollection
    var onPlay: (MediaItem) -> Void
    @EnvironmentObject private var library: LibraryStore

    private var columns: [GridItem] { Theme.posterGridColumns }

    private var items: [MediaItem] {
        smart.items(from: library.items)
    }

    var body: some View {
        ZStack {
            Theme.Colors.appBackground.ignoresSafeArea()
            ScrollView {
                if items.isEmpty {
                    VStack(spacing: Theme.Spacing.md) {
                        Image(systemName: smart.systemImage)
                            .font(.appFont(52))
                            .foregroundStyle(Theme.Colors.textTertiary)
                        Text("Nothing here right now")
                            .font(.appFont(22, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("This updates automatically as your library changes.")
                            .font(.appFont(18))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, Theme.Spacing.xl)
                } else {
                    LazyVGrid(columns: columns, spacing: Theme.Spacing.lg) {
                        ForEach(items) { item in
                            MediaCard(item: item) { onPlay(item) }
                        }
                    }
                    .padding(Theme.Spacing.edge)
                }
            }
        }
        .navigationTitle(smart.name)
    }
}
