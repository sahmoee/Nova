//
//  CatalogBrowseView.swift
//  Nova
//
//  Omni-style catalog group page: every configured TMDB shelf and installed addon
//  catalog for one content type, stacked as rows. Movies and Series are sidebar
//  roots on tvOS/iPad/Mac and Home filter destinations on iPhone.
//

import SwiftUI

struct CatalogBrowseView: View {
    let contentType: ContentType
    @Binding var path: NavigationPath

    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var shelfStore = HomeShelfStore.shared
    @ObservedObject private var addonStore: AddonStore

    init(contentType: ContentType, path: Binding<NavigationPath>, addonStore: AddonStore) {
        self.contentType = contentType
        self._path = path
        self._addonStore = ObservedObject(wrappedValue: addonStore)
    }

    private var title: String { contentType == .movie ? "Movies" : "Series" }

    /// Configured shelves of this type first (keeping the user's order and layout),
    /// then any addon catalog of this type the user hasn't added to Home.
    private var shelves: [ShelfConfig] {
        let configured = shelfStore.shelves.filter { $0.contentType == contentType }
        let configuredKeys = Set(configured.map(\.kind.cacheKey))
        let addonType = contentType == .movie ? "movie" : "series"
        let extra = addonStore.enabled.flatMap { addon in
            addon.catalogs
                .filter { $0.type == addonType }
                .map { ShelfConfig(kind: .addonCatalog(addonID: addon.id, type: $0.type, catalogID: $0.catalogID),
                                   title: "\($0.name) · \(addon.name)") }
        }
        .filter { !configuredKeys.contains($0.kind.cacheKey) }
        return configured + extra
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: OmniStyle.rowSpacing) {
                    header
                    if shelves.isEmpty {
                        emptyState
                    } else {
                        ForEach(shelves) { shelf in
                            OmniShelfRow(shelf: shelf)
                        }
                    }
                }
                .padding(.bottom, 80)
            }
            .scrollClipDisabled()
            .background(Theme.Colors.background.ignoresSafeArea())
            #if os(tvOS)
            .tvRootMenu()
            #else
            .navigationTitle(title)
            .toolbarTitleDisplayMode(.inlineLarge)
            #endif
            .navigationDestination(for: CatalogItem.self) { item in
                ContentDetailView(item: item)
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        #if os(tvOS)
        Text(title)
            .font(.appFont(52, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, OmniStyle.edge)
            .padding(.top, 48)
            .accessibilityAddTraits(.isHeader)
        #else
        EmptyView()
        #endif
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No \(title.lowercased()) catalogs yet")
                .font(.appFont(OmniStyle.rowTitleSize, weight: .semibold))
                .foregroundStyle(.white)
            Text("Add a TMDB key or install an addon with \(title.lowercased()) catalogs in Settings › Sources.")
                .font(.appFont(OmniStyle.rowTitleSize * 0.62))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, OmniStyle.edge)
    }
}
