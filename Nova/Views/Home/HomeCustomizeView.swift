//
//  HomeCustomizeView.swift
//  Nova
//
//  Lets the user choose which catalog shelves appear on Home/Discover, reorder them,
//  and add new ones (TMDB categories, Trakt, or addon catalogs).
//

import SwiftUI

struct HomeCustomizeView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var store = HomeShelfStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($store.shelves) { $shelf in
                        HStack {
                            Toggle(isOn: $shelf.isEnabled) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(shelf.title)
                                        .font(.appFont(19, weight: .semibold))
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                    Text(shelf.kind.sourceLabel)
                                        .font(.appFont(14))
                                        .foregroundStyle(Theme.Colors.textTertiary)
                                }
                            }
                            .tint(Theme.Colors.accent)
                        }
                        .listRowBackground(Theme.Colors.card)
                    }
                    .onMove { store.move(from: $0, to: $1) }
                    .onDelete { store.shelves.remove(atOffsets: $0) }
                } header: {
                    Text("Shelves").foregroundStyle(Theme.Colors.textSecondary)
                } footer: {
                    Text("Toggle shelves on or off, drag to reorder, or swipe to remove. These appear on Home and Discover.")
                        .foregroundStyle(Theme.Colors.textTertiary)
                }

                Section {
                    Button {
                        showAdd = true
                    } label: {
                        Label("Add a Shelf", systemImage: "plus.circle.fill")
                            .foregroundStyle(Theme.Colors.accent)
                    }
                    .listRowBackground(Theme.Colors.card)

                    Button(role: .destructive) {
                        store.resetToDefaults()
                    } label: {
                        Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                    }
                    .listRowBackground(Theme.Colors.card)
                } footer: {
                    Text("Shelves show recommendations tuned by your Not Interested / More Like This feedback.")
                        .font(.appFont(13))
                        .foregroundStyle(Theme.Colors.textTertiary)
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
            .background(Theme.Colors.appBackground.ignoresSafeArea())
            .navigationTitle("Customize Home")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            #endif
            .sheet(isPresented: $showAdd) {
                AddShelfView()
            }
        }
    }
}

/// Picker for adding a new shelf: built-in TMDB/Trakt kinds plus any addon catalogs.
struct AddShelfView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var store = HomeShelfStore.shared
    @Environment(\.dismiss) private var dismiss

    private let builtIns: [ShelfKind] = [
        .traktWatchlist, .traktTrendingShows,
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
            .navigationBarTitleDisplayMode(.inline)
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
