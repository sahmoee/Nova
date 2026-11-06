//
//  HomeCustomizeView.swift
//  Nova
//
//  Omni-style Catalog Management: every Home row with its source, Top Row pin and
//  layout. Selecting a catalog opens an editor to rename it, show or hide it, pin
//  it to the Top Row under the hero, choose poster or landscape cards, cap its
//  items, reorder it (remote-friendly up/down) or remove it.
//

import SwiftUI

struct HomeCustomizeView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var store = HomeShelfStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showAdd = false
    @State private var editingID: UUID?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.shelves) { shelf in
                        Button { editingID = shelf.id } label: { row(shelf) }
                            .listRowBackground(Theme.Colors.card)
                    }
                    .onMove { store.move(from: $0, to: $1) }
                    .onDelete { store.shelves.remove(atOffsets: $0) }
                } header: {
                    Text("Catalogs").foregroundStyle(Theme.Colors.textSecondary)
                } footer: {
                    Text("Pinned catalogs form the Top Row under the Home hero and feed its featured titles. Select a catalog to rename, restyle, reorder or hide it.")
                        .foregroundStyle(Theme.Colors.textTertiary)
                }

                Section {
                    Button { showAdd = true } label: {
                        Label("Add a Catalog", systemImage: "plus.circle.fill")
                    }
                    .listRowBackground(Theme.Colors.card)

                    Button(role: .destructive) { store.resetToDefaults() } label: {
                        Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                    }
                    .listRowBackground(Theme.Colors.card)
                }

                if RecommendationFeedbackStore.shared.hasFeedback {
                    Section {
                        Button(role: .destructive) {
                            RecommendationFeedbackStore.shared.reset()
                        } label: {
                            Label("Clear Recommendation Feedback", systemImage: "hand.raised.slash")
                        }
                        .listRowBackground(Theme.Colors.card)
                    } footer: {
                        Text("Un-hides everything you marked Not Interested or Already Watched and clears genre preferences.")
                            .font(.appFont(13))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
            }
            #if os(iOS)
            .scrollContentBackground(.hidden)
            #endif
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle("Catalogs")
            #if os(iOS)
            .novaInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            #endif
            .sheet(isPresented: $showAdd) { AddShelfView() }
            .sheet(item: Binding(get: { editingID.map(EditTarget.init) }, set: { editingID = $0?.id })) { target in
                NavigationStack { CatalogEditorView(shelfID: target.id) }
            }
        }
    }

    private struct EditTarget: Identifiable { let id: UUID }

    private func row(_ shelf: ShelfConfig) -> some View {
        HStack(spacing: 14) {
            Image(systemName: shelf.resolvedLayout == .landscape ? "rectangle" : "rectangle.portrait")
                .font(.appFont(20, weight: .medium))
                .foregroundStyle(shelf.isEnabled ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(shelf.title)
                    .font(.appFont(19, weight: .semibold))
                    .foregroundStyle(shelf.isEnabled ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                    .lineLimit(1)
                Text(detail(for: shelf))
                    .font(.appFont(14))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
            if shelf.isPinnedToTopRow {
                Image(systemName: "pin.fill")
                    .foregroundStyle(AccentManager.fallback)
                    .accessibilityLabel("Pinned to Top Row")
            }
            if !shelf.isEnabled {
                Text("Hidden").font(.appFont(13, weight: .semibold)).foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func detail(for shelf: ShelfConfig) -> String {
        var parts = [shelf.kind.sourceLabel, shelf.resolvedLayout.title]
        if let limit = shelf.itemLimit { parts.append("\(limit) items") }
        return parts.joined(separator: " · ")
    }
}

/// Edits one catalog row. Changes apply immediately through `HomeShelfStore`.
struct CatalogEditorView: View {
    let shelfID: UUID
    @StateObject private var store = HomeShelfStore.shared
    @Environment(\.dismiss) private var dismiss

    private static let limits: [Int?] = [nil, 10, 20, 30, 50]

    private var shelf: ShelfConfig? { store.shelves.first { $0.id == shelfID } }
    private var index: Int? { store.shelves.firstIndex { $0.id == shelfID } }

    private func binding<T>(_ keyPath: WritableKeyPath<ShelfConfig, T>, default value: T) -> Binding<T> {
        Binding(get: { shelf?[keyPath: keyPath] ?? value },
                set: { newValue in store.update(shelfID) { $0[keyPath: keyPath] = newValue } })
    }

    var body: some View {
        Form {
            if let shelf {
                Section("Name") {
                    TextField("Catalog name", text: binding(\.title, default: shelf.kind.defaultTitle))
                    if shelf.title != shelf.kind.defaultTitle {
                        Button("Restore Original Name") {
                            store.update(shelfID) { $0.title = $0.kind.defaultTitle }
                        }
                    }
                }
                Section {
                    Toggle("Show on Home", isOn: binding(\.isEnabled, default: true))
                    Toggle("Pin to Top Row", isOn: binding(\.isPinnedToTopRow, default: false))
                } footer: {
                    Text("The first Top Row catalog supplies the titles featured in the Home hero.")
                }
                Section("Cards") {
                    Picker("Layout", selection: binding(\.layout, default: nil)) {
                        Text("Default").tag(OmniShelfLayout?.none)
                        ForEach(OmniShelfLayout.allCases) { Text($0.title).tag(OmniShelfLayout?.some($0)) }
                    }
                    Picker("Items Shown", selection: binding(\.itemLimit, default: nil)) {
                        ForEach(Self.limits, id: \.self) { limit in
                            Text(limit.map { "\($0)" } ?? "All").tag(limit)
                        }
                    }
                }
                Section("Order") {
                    Button { store.move(id: shelfID, offset: -1) } label: {
                        Label("Move Up", systemImage: "arrow.up")
                    }
                    .disabled(index == 0)
                    Button { store.move(id: shelfID, offset: 1) } label: {
                        Label("Move Down", systemImage: "arrow.down")
                    }
                    .disabled(index == store.shelves.count - 1)
                }
                Section {
                    Button("Remove Catalog", role: .destructive) {
                        store.shelves.removeAll { $0.id == shelfID }
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(shelf?.title ?? "Catalog")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
    }
}

/// Picker for adding a new shelf: built-in TMDB kinds plus any addon catalogs.
struct AddShelfView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var store = HomeShelfStore.shared
    @Environment(\.dismiss) private var dismiss

    private let builtIns: [ShelfKind] = [
        .tmdbTrending, .tmdbTrendingShows, .tmdbPopularMovies,
        .tmdbNowPlaying, .tmdbTopRated, .tmdbPopularShows, .tmdbAiringToday
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(builtIns, id: \.self) { kind in
                        Button {
                            add(kind)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(kind.defaultTitle)
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                    Text(kind.sourceLabel)
                                        .font(.appFont(14))
                                        .foregroundStyle(Theme.Colors.textTertiary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(Theme.Colors.accent)
                            }
                        }
                        .listRowBackground(Theme.Colors.card)
                    }
                } header: {
                    Text("Built-in").foregroundStyle(Theme.Colors.textSecondary)
                }

                // Addon catalogs (e.g. live TV, custom catalogs).
                let addonCatalogs = env.addonStore.addons.flatMap { addon in
                    addon.catalogs.map { (addon, $0) }
                }
                if !addonCatalogs.isEmpty {
                    Section {
                        ForEach(addonCatalogs, id: \.1.id) { addon, cat in
                            Button {
                                addAddonCatalog(addon: addon, cat: cat)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(cat.name)
                                            .foregroundStyle(Theme.Colors.textPrimary)
                                        Text("\(addon.name) · \(cat.type)")
                                            .font(.appFont(14))
                                            .foregroundStyle(Theme.Colors.textTertiary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(Theme.Colors.accent)
                                }
                            }
                            .listRowBackground(Theme.Colors.card)
                        }
                    } header: {
                        Text("From Your Addons").foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
            #if os(iOS)
            .scrollContentBackground(.hidden)
            #endif
            .background(Theme.Colors.appBackground.ignoresSafeArea())
            .navigationTitle("Add a Shelf")
            #if os(iOS)
            .novaInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            #endif
        }
    }

    private func add(_ kind: ShelfKind) {
        store.shelves.append(ShelfConfig(kind: kind))
        dismiss()
    }
    private func addAddonCatalog(addon: InstalledAddon, cat: AddonCatalogRef) {
        let kind = ShelfKind.addonCatalog(addonID: addon.id, type: cat.type, catalogID: cat.catalogID)
        store.shelves.append(ShelfConfig(kind: kind, title: cat.name))
        dismiss()
    }
}
