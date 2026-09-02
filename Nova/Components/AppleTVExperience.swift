//
//  AppleTVExperience.swift
//  Nova
//
//  Reusable Apple TV-style experience components shared by iPhone, iPad, and tvOS.
//  Platform-only behaviors are omitted through PlatformCapabilities.
//

import SwiftUI

@MainActor
final class ArtworkHeaderCoordinator: ObservableObject {
    static let shared = ArtworkHeaderCoordinator()

    struct Selection: Equatable {
        let artworkURL: URL?
        let title: String?
    }

    @Published private var selections: [ArtworkHeaderScope: Selection] = [:]

    func select(_ item: MediaItem, in scope: ArtworkHeaderScope) {
        select(url: item.backdropURL ?? item.posterURL, title: item.displayTitle, in: scope)
    }

    func select(_ item: CatalogItem, in scope: ArtworkHeaderScope) {
        select(url: item.backdropURL ?? item.posterURL, title: item.title, in: scope)
    }

    func select(url: URL?, title: String?, in scope: ArtworkHeaderScope) {
        let selection = Selection(artworkURL: url, title: title)
        guard selections[scope] != selection else { return }
        withAnimation(.easeInOut(duration: Theme.isReduceMotion ? 0 : 0.42)) {
            selections[scope] = selection
        }
    }

    func selection(in scope: ArtworkHeaderScope) -> Selection? { selections[scope] }
}

enum ArtworkHeaderScope: String, Hashable {
    case library, discover, collections, ai
}

/// A reusable full-width artwork layer for media-bearing pages. It follows the
/// latest focused or tapped title and crossfades without changing page navigation.
struct ReactiveArtworkBackdrop: View {
    let scope: ArtworkHeaderScope
    var fallbackAsset: String? = nil
    @ObservedObject private var coordinator = ArtworkHeaderCoordinator.shared

    var body: some View {
        ZStack {
            if let url = coordinator.selection(in: scope)?.artworkURL {
                CachedAsyncImage(url: url, maxPixel: 1600) { image in
                    ZStack {
                        // Fill the header without stretching the artwork, then lay a
                        // complete aspect-fit copy over it. Portrait posters and unusually
                        // wide backdrops therefore keep every edge visible while the soft
                        // bleed prevents letterboxing from looking like empty space.
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .blur(radius: 20)
                            .scaleEffect(1.08)
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
                } placeholder: {
                    fallback
                }
                .id(url)
                .transition(.opacity)
            } else {
                fallback
            }
        }
    }

    @ViewBuilder private var fallback: some View {
        if let fallbackAsset {
            let image = Image(fallbackAsset)
            ZStack {
                image.resizable().aspectRatio(contentMode: .fill).blur(radius: 20).scaleEffect(1.08)
                image.resizable().aspectRatio(contentMode: .fit)
            }
        } else {
            LinearGradient(colors: [Theme.Colors.cardElevated, Theme.Colors.background],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

struct ReactiveArtworkPageHeader: View {
    let title: String
    let scope: ArtworkHeaderScope
    var subtitle: String? = nil
    var systemImage: String? = nil
    var height: CGFloat = PlatformCapabilities.platform == .iPad ? 300 : 220

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ReactiveArtworkBackdrop(scope: scope)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipped()

            LinearGradient(colors: [.clear, Theme.Colors.background.opacity(0.48), Theme.Colors.background],
                           startPoint: .top, endPoint: .bottom)

            HStack(alignment: .center, spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.appFont(22, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.appFont(PlatformCapabilities.platform == .iPad ? 48 : 34, weight: .heavy))
                        .foregroundStyle(.white)
                    if let subtitle {
                        Text(subtitle)
                            .font(.appFont(15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.76))
                            .lineLimit(2)
                    }
                }
            }
            .shadow(color: .black.opacity(0.7), radius: 8, y: 3)
            .padding(.horizontal, Theme.Spacing.edge)
            .padding(.bottom, Theme.Spacing.md)
        }
        .frame(height: height)
        .clipped()
        .accessibilityElement(children: .combine)
    }
}

/// Deterministic header for utility destinations. Search, AI, Collections, Settings,
/// and similar pages must never inherit the last focused movie or show.
struct NovaGradientPageHeader: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var height: CGFloat = PlatformCapabilities.platform == .iPad ? 250 : 190

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color.white.opacity(0.10), Theme.Colors.cardElevated, Theme.Colors.background],
                           startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [.clear, Theme.Colors.background], startPoint: .top, endPoint: .bottom)
            HStack(alignment: .center, spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.appFont(22, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.appFont(PlatformCapabilities.platform == .iPad ? 44 : 32, weight: .heavy))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle)
                            .font(.appFont(15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.76))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.edge)
            .padding(.bottom, Theme.Spacing.md)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: height)
        .clipped()
        .accessibilityElement(children: .combine)
    }
}

/// Artwork-led Home hero inspired by modern streaming storefronts. It deliberately
/// contains no embedded controls: tapping opens Nova's own detail page, while the
/// persistent app tab bar remains completely independent and unchanged.
struct ImmersiveFeaturedHero: View {
    let item: MediaItem
    let height: CGFloat
    var onOpen: (MediaItem) -> Void
    var onPlay: (MediaItem) -> Void

    @Environment(\.dynamicAccent) private var accent

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Button { onOpen(item) } label: {
                ZStack {
                CachedAsyncImage(url: item.backdropURL ?? item.posterURL, maxPixel: 1600) { image in
                    ZStack {
                        // A full-bleed copy prevents bars around unusually tall or
                        // narrow artwork without stretching the visible composition.
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .blur(radius: 22)
                            .scaleEffect(1.08)

                        // The primary copy is always complete and keeps its native
                        // aspect ratio. It is never widened to fit the device.
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
                } placeholder: {
                    Rectangle().fill(Theme.Colors.card).shimmering()
                }
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipped()

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.35),
                        .init(color: .black.opacity(0.22), location: 0.62),
                        .init(color: Theme.Colors.background.opacity(0.96), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                RadialGradient(colors: [.clear, .black.opacity(0.34)],
                               center: .center,
                               startRadius: 120,
                               endRadius: 520)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(item.displayTitle)")

            VStack(alignment: .leading, spacing: 8) {
                Text("FEATURED")
                    .font(Theme.Font.eyebrow())
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.72))
                Text(item.displayTitle)
                    .font(Theme.Font.heroTitle())
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.56)
                    .shadow(color: .black.opacity(0.9), radius: 12, y: 4)
                if !item.subtitleLine.isEmpty {
                    Text(item.subtitleLine)
                        .font(.appFont(15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.84))
                        .lineLimit(1)
                }
                HStack(spacing: 10) {
                    Button { onPlay(item) } label: {
                        Label(item.hasResumePoint ? "Resume" : "Play", systemImage: "play.fill")
                            .font(.appFont(16, weight: .bold))
                            .padding(.horizontal, 20)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(FocusableButtonStyle(prominent: true))
                    Button { onOpen(item) } label: {
                        Label("More Info", systemImage: "info.circle")
                            .font(.appFont(16, weight: .semibold))
                            .padding(.horizontal, 18)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(NovaChipButtonStyle())
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: PlatformCapabilities.platform == .iPad ? 560 : 410, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.edge)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .frame(height: height)
        .onAppear { AccentManager.shared.deriveAccent(from: item.backdropURL ?? item.posterURL) }
    }
}

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
                Button(action: action) {
                    HStack(spacing: 5) {
                        Text(actionTitle)
                        Image(systemName: "chevron.right")
                            .font(.appFont(12, weight: .bold))
                    }
                    .font(.appFont(16, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .buttonStyle(NovaChipButtonStyle())
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
                    ForEach(Array(rail.items.enumerated()), id: \.element.id) { index, item in
                        MediaCard(item: item,
                                  wide: usesLandscapeCards(for: rail.kind),
                                  widthOverride: cardWidth(for: rail.kind),
                                  heightOverride: cardHeight(for: rail.kind),
                                  quickActions: true,
                                  rank: rail.kind == .topPicks ? index + 1 : nil) {
                            onSelect(item)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.edge)
                .padding(.vertical, PlatformCapabilities.platform == .appleTV ? 12 : 2)
            }
            .scrollClipDisabled()
        }
    }

    private func cardWidth(for kind: SmartHomeRailKind) -> CGFloat {
        let scale = PlatformCapabilities.railPosterScale
        #if os(tvOS)
        return Theme.CardSize.wideWidth * scale
        #else
        switch kind {
        case .finishTonight, .recentlyWatched:
            return Theme.CardSize.wideWidth * max(scale, 0.72)
        default:
            return Theme.CardSize.posterWidth * scale
        }
        #endif
    }

    private func cardHeight(for kind: SmartHomeRailKind) -> CGFloat {
        let scale = PlatformCapabilities.railPosterScale
        #if os(tvOS)
        return Theme.CardSize.wideHeight * scale
        #else
        switch kind {
        case .finishTonight, .recentlyWatched:
            return Theme.CardSize.wideHeight * max(scale, 0.72)
        default:
            return Theme.CardSize.posterHeight * scale
        }
        #endif
    }

    private func usesLandscapeCards(for kind: SmartHomeRailKind) -> Bool {
        #if os(tvOS)
        return true
        #else
        return kind == .finishTonight || kind == .recentlyWatched
        #endif
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
                AppleTVSectionHeader(title: PlatformCapabilities.platform == .appleTV ? "Continue Watching" : "Up Next",
                                     subtitle: PlatformCapabilities.platform == .appleTV ? nil : "Continue watching and items in your queue",
                                     systemImage: PlatformCapabilities.platform == .appleTV ? nil : "play.square.stack.fill",
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
                .scrollClipDisabled()
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
            AppleTVSectionHeader(title: "Explore Nova",
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
            .scrollClipDisabled()
        }
    }
}

/// Compact two-column destination tiles used under the Home screen's Discover
/// heading. The subtle artwork-like color fields keep the image-led hierarchy of
/// the reference without copying its assets or changing Nova's navigation.
struct StreamingDiscoverGrid: View {
    let items: [AppleTVQuickAccessItem]

    private let swatches: [[Color]] = [
        [Color(red: 0.46, green: 0.08, blue: 0.09), Color(red: 0.14, green: 0.02, blue: 0.04)],
        [Color(red: 0.08, green: 0.11, blue: 0.38), Color(red: 0.02, green: 0.03, blue: 0.13)],
        [Color(red: 0.05, green: 0.31, blue: 0.31), Color(red: 0.02, green: 0.09, blue: 0.12)],
        [Color(red: 0.31, green: 0.13, blue: 0.42), Color(red: 0.08, green: 0.03, blue: 0.14)]
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            AppleTVSectionHeader(title: "Discover")

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())],
                      spacing: 14) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Button(action: item.action) {
                        ZStack(alignment: .bottomLeading) {
                            LinearGradient(colors: swatches[index % swatches.count],
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing)
                            Circle()
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 150, height: 150)
                                .blur(radius: 12)
                                .offset(x: 55, y: -40)
                            Image(systemName: item.systemImage)
                                .font(.appFont(54, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.14))
                                .frame(maxWidth: .infinity, maxHeight: .infinity,
                                       alignment: .topTrailing)
                                .padding(16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.appFont(23, weight: .bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(item.subtitle)
                                    .font(.appFont(13))
                                    .foregroundStyle(.white.opacity(0.70))
                                    .lineLimit(1)
                            }
                            .padding(16)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: PlatformCapabilities.platform == .iPad ? 190 : 144)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8)
                        }
                    }
                    .buttonStyle(NovaListRowStyle())
                }
            }
            .padding(.horizontal, Theme.Spacing.edge)
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
                    .strokeBorder(focused ? Theme.Colors.accentSecondary : Color.white.opacity(0.10),
                                  lineWidth: focused ? 3 : 1)
            )
            .shadow(color: focused ? Theme.Colors.accent.opacity(0.48) : .black.opacity(0.22),
                    radius: focused ? 24 : 10, y: 8)
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
                        .buttonStyle(NovaListRowStyle())
                    }
                }
                .padding(.horizontal, Theme.Spacing.edge)
                .padding(.vertical, PlatformCapabilities.platform == .appleTV ? 12 : 2)
            }
            .scrollClipDisabled()
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
        .buttonStyle(NovaListRowStyle())
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
                        .buttonStyle(NovaListRowStyle())
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
        .buttonStyle(NovaListRowStyle())
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
                                .buttonStyle(NovaListRowStyle())
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
                            .buttonStyle(NovaListRowStyle())
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
