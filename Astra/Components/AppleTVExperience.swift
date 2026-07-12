//
//  AppleTVExperience.swift
//  Astra
//
//  Reusable Apple TV-style experience components shared by iPhone, iPad, and tvOS.
//  Platform-only behaviors are omitted through PlatformCapabilities.
//

import SwiftUI

struct AppleTVSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.appFont(20, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Font.sectionTitle())
                    .foregroundStyle(Theme.Colors.textPrimary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.appFont(15))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: Theme.Spacing.sm)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.appFont(16, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Spacing.edge)
    }
}

struct AppleTVSmartRailView: View {
    let rail: SmartHomeRail
    var onSelect: (MediaItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            AppleTVSectionHeader(title: rail.title,
                                 subtitle: rail.subtitle,
                                 systemImage: rail.systemImage)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Theme.Spacing.md) {
                    ForEach(rail.items) { item in
                        MediaCard(item: item,
                                  wide: rail.kind == .finishTonight || rail.kind == .recentlyWatched,
                                  widthOverride: cardWidth(for: rail.kind),
                                  heightOverride: cardHeight(for: rail.kind),
                                  quickActions: true) {
                            onSelect(item)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.edge)
                .padding(.vertical, PlatformCapabilities.platform == .appleTV ? 12 : 2)
            }
        }
    }

    private func cardWidth(for kind: SmartHomeRailKind) -> CGFloat {
        let scale = PlatformCapabilities.railPosterScale
        switch kind {
        case .finishTonight, .recentlyWatched:
            return Theme.CardSize.wideWidth * max(scale, 0.72)
        default:
            return Theme.CardSize.posterWidth * scale
        }
    }

    private func cardHeight(for kind: SmartHomeRailKind) -> CGFloat {
        let scale = PlatformCapabilities.railPosterScale
        switch kind {
        case .finishTonight, .recentlyWatched:
            return Theme.CardSize.wideHeight * max(scale, 0.72)
        default:
            return Theme.CardSize.posterHeight * scale
        }
    }
}

struct AppleTVUpNextRail: View {
    let items: [MediaItem]
    var onPlay: (MediaItem) -> Void
    var onRestart: (MediaItem) -> Void
    var onRemove: (MediaItem) -> Void
    var onManage: () -> Void

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                AppleTVSectionHeader(title: "Up Next",
                                     subtitle: "Continue watching and items in your queue",
                                     systemImage: "play.square.stack.fill",
                                     actionTitle: "Manage",
                                     action: onManage)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: Theme.Spacing.md) {
                        ForEach(items) { item in
                            ContinueWatchingCard(
                                item: item,
                                onPlay: { onPlay(item) },
                                onRestart: { onRestart(item) },
                                onRemove: { onRemove(item) }
                            )
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.edge)
                    .padding(.vertical, PlatformCapabilities.platform == .appleTV ? 12 : 2)
                }
            }
        }
    }

}

struct AppleTVQuickAccessItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void
}

struct AppleTVQuickAccessRow: View {
    let items: [AppleTVQuickAccessItem]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            AppleTVSectionHeader(title: "Explore Astra",
                                 subtitle: "Open the parts of your media hub you use most",
                                 systemImage: "square.grid.2x2.fill")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.Spacing.md) {
                    ForEach(items) { item in
                        AppleTVQuickAccessTile(item: item)
                    }
                }
                .padding(.horizontal, Theme.Spacing.edge)
                .padding(.vertical, PlatformCapabilities.platform == .appleTV ? 12 : 2)
            }
        }
    }
}

private struct AppleTVQuickAccessTile: View {
    let item: AppleTVQuickAccessItem
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: item.action) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [Theme.Colors.cardElevated, Theme.Colors.card],
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing)
                Image(systemName: item.systemImage)
                    .font(.appFont(58, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Theme.Colors.textPrimary.opacity(0.88))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(Theme.Spacing.md)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.appFont(22, weight: .bold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(item.subtitle)
                        .font(.appFont(14))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(2)
                }
                .padding(Theme.Spacing.md)
            }
            .frame(width: Theme.scaled(300, min: 210),
                   height: Theme.scaled(170, min: 132))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.largeCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.largeCard, style: .continuous)
                    .strokeBorder(focused ? Color.white.opacity(0.92) : Color.white.opacity(0.08),
                                  lineWidth: focused ? 3 : 1)
            )
            .shadow(color: .black.opacity(focused ? 0.5 : 0.22), radius: focused ? 22 : 10, y: 8)
        }
        .buttonStyle(.plain)
        .focused($focused)
        .scaleEffect(focused ? Theme.CardSize.focusScale : 1)
        .animation(.easeOut(duration: 0.16), value: focused)
    }
}

struct AppleTVSourceHub: View {
    let items: [SourceHealthItem]
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            let summary = SourceHealth.summary(items)
            AppleTVSectionHeader(
                title: "Your Sources",
                subtitle: summary.needsAttention == 0
                    ? "\(summary.connected) connected and ready"
                    : "\(summary.needsAttention) source\(summary.needsAttention == 1 ? "" : "s") need attention",
                systemImage: "point.3.connected.trianglepath.dotted",
                actionTitle: "Manage",
                action: onOpenSettings
            )
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.Spacing.sm) {
                    ForEach(items) { item in
                        Button(action: onOpenSettings) {
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: item.systemImage)
                                    .font(.appFont(22, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                    .frame(width: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.appFont(17, weight: .semibold))
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                    Text(item.detail ?? item.status.label)
                                        .font(.appFont(13))
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                        .lineLimit(1)
                                }
                                Image(systemName: item.status.systemImage)
                                    .foregroundStyle(item.status.color)
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm)
                            .frame(minWidth: Theme.scaled(240, min: 190), alignment: .leading)
                            .background(.thinMaterial,
                                        in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                            )
                        }
                        .buttonStyle(AstraListRowStyle())
                    }
                }
                .padding(.horizontal, Theme.Spacing.edge)
                .padding(.vertical, PlatformCapabilities.platform == .appleTV ? 12 : 2)
            }
        }
    }
}

struct AppleTVProfileButton: View {
    @ObservedObject var store: ViewingProfileStore
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: store.activeProfile.systemImage)
                    .font(.appFont(20, weight: .semibold))
                Text(store.activeProfile.name)
                    .font(.appFont(15, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(AstraListRowStyle())
    }
}

struct ViewingProfileSwitcherView: View {
    @ObservedObject var store: ViewingProfileStore
    @Environment(\.dismiss) private var dismiss
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Theme.scaled(180, min: 140)), spacing: Theme.Spacing.md)],
                          spacing: Theme.Spacing.md) {
                    ForEach(store.profiles) { profile in
                        profileCard(profile)
                    }
                    if store.profiles.count < 6 {
                        Button { showAdd = true } label: {
                            VStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.appFont(48))
                                Text("Add Profile")
                                    .font(.appFont(18, weight: .semibold))
                            }
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: Theme.scaled(180, min: 150))
                            .background(Theme.Colors.card,
                                        in: RoundedRectangle(cornerRadius: Theme.Radius.largeCard, style: .continuous))
                        }
                        .buttonStyle(AstraListRowStyle())
                    }
                }
                .padding(Theme.Spacing.edge)
            }
            .background(Theme.Colors.appBackground.ignoresSafeArea())
            .navigationTitle("Who’s Watching?")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                #endif
            }
            .sheet(isPresented: $showAdd) {
                AddViewingProfileView(store: store)
            }
        }
    }

    private func profileCard(_ profile: ViewingProfile) -> some View {
        Button {
            store.select(profile)
            dismiss()
        } label: {
            VStack(spacing: Theme.Spacing.sm) {
                ZStack {
                    Circle().fill(Theme.Colors.cardElevated)
                    Image(systemName: profile.systemImage)
                        .font(.appFont(58, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                .frame(width: Theme.scaled(112, min: 86), height: Theme.scaled(112, min: 86))
                Text(profile.name)
                    .font(.appFont(19, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                if profile.id == store.activeProfileID {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .font(.appFont(13, weight: .semibold))
                        .foregroundStyle(Theme.Colors.success)
                }
            }
            .frame(maxWidth: .infinity, minHeight: Theme.scaled(180, min: 150))
            .padding(Theme.Spacing.md)
            .background(.thinMaterial,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.largeCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.largeCard, style: .continuous)
                    .strokeBorder(profile.id == store.activeProfileID ? Color.white.opacity(0.7) : Color.white.opacity(0.08),
                                  lineWidth: profile.id == store.activeProfileID ? 2 : 1)
            )
        }
        .buttonStyle(AstraListRowStyle())
        .contextMenu {
            if store.profiles.count > 1 {
                Button(role: .destructive) { store.remove(profile) } label: {
                    Label("Delete Profile", systemImage: "trash")
                }
            }
        }
    }
}

private struct AddViewingProfileView: View {
    @ObservedObject var store: ViewingProfileStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var symbol = "person.crop.circle.fill"
    @State private var kids = false

    private let symbols = [
        "person.crop.circle.fill", "face.smiling.inverse", "star.circle.fill",
        "moon.circle.fill", "sun.max.circle.fill", "pawprint.circle.fill"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Name", text: $name)
                    Toggle("Kids profile", isOn: $kids)
                }
                Section("Icon") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], spacing: 14) {
                        ForEach(symbols, id: \.self) { candidate in
                            Button { symbol = candidate } label: {
                                Image(systemName: candidate)
                                    .font(.appFont(34))
                                    .frame(width: 58, height: 58)
                                    .background(symbol == candidate ? Theme.Colors.accent.opacity(0.35) : Theme.Colors.card,
                                                in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("New Profile")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    Button("Add") { add() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                #endif
            }
        }
    }

    private func add() {
        _ = store.addProfile(name: name, systemImage: symbol, isKidsProfile: kids)
        dismiss()
    }
}

struct BecauseYouWatchedCatalogRail: View {
    let anchor: MediaItem
    var onSelect: (CatalogItem) -> Void

    @EnvironmentObject private var env: AppEnvironment
    @State private var items: [CatalogItem] = []
    @State private var loaded = false

    var body: some View {
        Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    AppleTVSectionHeader(title: "More Like \(anchor.seriesTitle ?? anchor.title)",
                                         subtitle: "Recommendations from TMDB",
                                         systemImage: "sparkles.rectangle.stack.fill")
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: Theme.Spacing.md) {
                            ForEach(items) { item in
                                Button { onSelect(item) } label: {
                                    CatalogPosterCard(item: item, scale: PlatformCapabilities.railPosterScale * 0.82)
                                }
                                .buttonStyle(AstraListRowStyle())
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.edge)
                        .padding(.vertical, PlatformCapabilities.platform == .appleTV ? 12 : 2)
                    }
                }
            } else if !loaded {
                EmptyView()
            }
        }
        .task(id: anchor.contentKey) {
            guard let tmdbID = anchor.contentID?.tmdb, env.tmdb.hasKey else {
                loaded = true
                return
            }
            let isMovie = anchor.contentID?.type != .series && !anchor.isSeries
            items = (try? await env.tmdb.related(tmdbID: tmdbID, isMovie: isMovie)) ?? []
            loaded = true
        }
    }
}

struct SmartCollectionsView: View {
    @EnvironmentObject private var library: LibraryStore
    @StateObject private var profiles = ViewingProfileStore.shared
    @State private var selectedItem: MediaItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.rowGap) {
                ScreenHeader(title: "Smart Collections",
                             subtitle: "Automatically updated from your library and viewing activity")
                    .padding(.horizontal, Theme.Spacing.edge)
                    .padding(.top, Theme.Spacing.lg)
                ForEach(PersonalizedHomeEngine.rails(library: library, profile: profiles.activeProfile)) { rail in
                    AppleTVSmartRailView(rail: rail) { selectedItem = $0 }
                }
            }
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.Colors.appBackground.ignoresSafeArea())
        .navigationDestination(item: $selectedItem) { item in
            ContentDetailView(item: item.asCatalogItem())
        }
    }
}

struct WatchHistoryTimelineView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var selectedItem: MediaItem?

    var body: some View {
        Group {
            if library.recentlyWatched.isEmpty {
                EmptyStateView(systemImage: "clock.arrow.circlepath",
                               title: "No watch history yet",
                               message: "Titles you play will appear here in most-recent order.")
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.sm) {
                        ForEach(library.recentlyWatched) { item in
                            Button { selectedItem = item } label: {
                                HStack(spacing: Theme.Spacing.md) {
                                    PosterImage(url: item.posterURL,
                                                width: Theme.scaled(74, min: 58),
                                                height: Theme.scaled(110, min: 86))
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(item.displayTitle)
                                            .font(.appFont(20, weight: .semibold))
                                            .foregroundStyle(Theme.Colors.textPrimary)
                                            .lineLimit(2)
                                        if let date = item.lastPlayedDate {
                                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                                .font(.appFont(14))
                                                .foregroundStyle(Theme.Colors.textSecondary)
                                        }
                                        Text(item.isWatched ? "Watched" : "\(Int(item.progressFraction * 100))% complete")
                                            .font(.appFont(14, weight: .semibold))
                                            .foregroundStyle(item.isWatched ? Theme.Colors.success : Theme.Colors.accent)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(Theme.Colors.textTertiary)
                                }
                                .padding(Theme.Spacing.md)
                                .background(.thinMaterial,
                                            in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                            }
                            .buttonStyle(AstraListRowStyle())
                            .contextMenu {
                                Button { library.markUnwatched(item) } label: {
                                    Label("Mark Unwatched", systemImage: "circle")
                                }
                                Button(role: .destructive) { library.clearProgress(for: item.id) } label: {
                                    Label("Remove from History", systemImage: "clock.badge.xmark")
                                }
                            }
                        }
                    }
                    .padding(Theme.Spacing.edge)
                }
            }
        }
        .background(Theme.Colors.appBackground.ignoresSafeArea())
        .navigationTitle("Watch History")
        .navigationDestination(item: $selectedItem) { item in
            ContentDetailView(item: item.asCatalogItem())
        }
    }
}

