//
//  AddonCatalogBrowserView.swift
//  Nova
//

import SwiftUI

struct AddonCatalogBrowserView: View {
    let addon: InstalledAddon
    @EnvironmentObject private var env: AppEnvironment
    @State private var selectedCatalogID: String
    @State private var query = ""
    @State private var genre = ""
    @State private var items: [CatalogItem] = []
    @State private var skip = 0
    @State private var isLoading = false
    @State private var reachedEnd = false
    @State private var errorMessage: String?

    private let pageSize = 100
    private let columns = [GridItem(.adaptive(minimum: Theme.CardSize.posterWidth * 0.9),
                                    spacing: Theme.Spacing.md)]

    init(addon: InstalledAddon, catalog: AddonCatalogRef? = nil) {
        self.addon = addon
        _selectedCatalogID = State(initialValue: (catalog ?? addon.catalogs.first)?.id ?? "")
    }

    private var selectedCatalog: AddonCatalogRef? {
        addon.catalogs.first(where: { $0.id == selectedCatalogID }) ?? addon.catalogs.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                ScreenHeader(title: addon.name, subtitle: "Addon catalogs") { EmptyView() }

                Picker("Catalog", selection: $selectedCatalogID) {
                    ForEach(addon.catalogs) { catalog in
                        Text(catalog.name).tag(catalog.id)
                    }
                }
                .pickerStyle(.menu)

                HStack(spacing: Theme.Spacing.sm) {
                    TextField("Search this catalog", text: $query)
                        .textFieldStyle(.plain)
                        .onSubmit { resetAndLoad() }
                    TextField("Genre (optional)", text: $genre)
                        .textFieldStyle(.plain)
                        .onSubmit { resetAndLoad() }
                    Button("Search") { resetAndLoad() }
                        .foregroundStyle(Theme.Colors.accent)
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.button))

                if let errorMessage {
                    ErrorStateView(message: errorMessage, onRetry: { resetAndLoad() }, onBack: nil)
                } else if items.isEmpty && isLoading {
                    SkeletonGrid(count: 10)
                } else if items.isEmpty {
                    EmptyStateView(systemImage: "rectangle.stack",
                                   title: "No catalog items",
                                   message: "Try a different search or genre.")
                        .frame(minHeight: 320)
                } else {
                    LazyVGrid(columns: columns, spacing: Theme.Spacing.lg) {
                        ForEach(items) { item in
                            NavigationLink(value: item) {
                                CatalogPosterCard(item: item)
                            }
                            .buttonStyle(NovaListRowStyle())
                            .onAppear {
                                if item.id == items.last?.id { Task { await loadNextPage() } }
                            }
                        }
                    }
                    if isLoading { ProgressView().frame(maxWidth: .infinity) }
                }
            }
            .padding(Theme.Spacing.edge)
            .frame(maxWidth: Theme.contentMaxWidth(1500), alignment: .leading)
        }
        .background(Theme.Colors.appBackground.ignoresSafeArea())
        .navigationDestination(for: CatalogItem.self) { ContentDetailView(item: $0) }
        .task(id: selectedCatalogID) { await reset() }
    }

    private func resetAndLoad() {
        Task { await reset() }
    }

    private func reset() async {
        items = []
        skip = 0
        reachedEnd = false
        errorMessage = nil
        await loadNextPage()
    }

    private func loadNextPage() async {
        guard !isLoading, !reachedEnd, let catalog = selectedCatalog,
              let resolved = env.addonStore.resolvedAddon(id: addon.id) else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await env.addonClient.catalog(
                from: resolved, type: catalog.type, catalogID: catalog.catalogID,
                search: query.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                genre: genre.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                skip: skip
            )
            let existing = Set(items.map(\.id))
            items.append(contentsOf: page.filter { !existing.contains($0.id) })
            skip += page.count
            reachedEnd = page.isEmpty || page.count < pageSize
            ImageLoader.shared.prefetch(Array(page.prefix(12)).compactMap(\.posterURL))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
