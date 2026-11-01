//
//  OmniHome.swift
//  Nova
//
//  Omni-style Home building blocks: a logo-first featured hero fed by the Top Row
//  catalogs, and a landscape Continue Watching row. On tvOS the hero collapses
//  once focus moves into the rows and then previews the focused title ("content
//  below hero"); touch platforms keep a swipeable carousel.
//

import SwiftUI

// MARK: - Hero

struct OmniHeroView: View {
    let items: [CatalogItem]
    /// Title focused in a row below; previewed while the hero is collapsed.
    let previewItem: CatalogItem?
    let collapsed: Bool
    let height: CGFloat
    var isActive: Bool = true
    var onPlay: (CatalogItem) -> Void
    var onOpen: (CatalogItem) -> Void
    /// Reports when focus enters or leaves the hero's buttons (tvOS).
    var onFocusChange: ((Bool) -> Void)? = nil

    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var library: LibraryStore
    @AppStorage(OmniLayoutKey.heroAutoAdvance) private var autoAdvance = true
    @AppStorage(OmniLayoutKey.showHeroLogo) private var showLogo = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focusedAction: HeroAction?
    @State private var index = 0
    @State private var logos: [String: URL] = [:]

    private enum HeroAction: Hashable { case play, info, add }

    private var featured: CatalogItem? {
        items.isEmpty ? nil : items[min(index, items.count - 1)]
    }

    /// What the hero shows: the focused row title while collapsed, else the
    /// current featured title.
    private var shown: CatalogItem? { collapsed ? (previewItem ?? featured) : featured }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let shown {
                backdrop(for: shown)
                copy(for: shown)
                    .padding(.leading, OmniStyle.edge)
                    .padding(.trailing, OmniStyle.edge)
                    .padding(.bottom, collapsed ? 28 : bottomInset)
                if !collapsed && items.count > 1 { indicators }
            } else {
                placeholder
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: shown?.id)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: collapsed)
        .task(id: shown?.id) { await loadLogo(for: shown) }
        .task(id: rotationKey) { await rotate() }
        .onChange(of: items.map(\.id)) { _, _ in index = 0 }
        .onChange(of: focusedAction) { old, new in
            if (old == nil) != (new == nil) { onFocusChange?(new != nil) }
        }
        #if os(iOS)
        .contentShape(Rectangle())
        .simultaneousGesture(DragGesture(minimumDistance: 25).onEnded(swipe))
        #endif
    }

    // MARK: Artwork

    private func backdrop(for item: CatalogItem) -> some View {
        ZStack {
            CachedAsyncImage(url: item.backdropURL ?? item.posterURL, maxPixel: 1920) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Theme.Colors.backgroundElevated
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .id(item.id)
            .transition(.opacity)

            // Left and bottom scrims keep copy readable without tinting the art.
            LinearGradient(colors: [.black.opacity(0.85), .black.opacity(0.35), .clear],
                           startPoint: .leading, endPoint: .init(x: 0.7, y: 0.5))
            LinearGradient(stops: [.init(color: .clear, location: 0.35),
                                   .init(color: .black.opacity(0.7), location: 0.8),
                                   .init(color: .black, location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .accessibilityHidden(true)
    }

    // MARK: Copy

    private func copy(for item: CatalogItem) -> some View {
        VStack(alignment: .leading, spacing: collapsed ? 10 : 16) {
            titleArt(for: item)
            Text(metadata(for: item))
                .font(.appFont(metaSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
            if !collapsed, let overview = item.overview, !overview.isEmpty {
                Text(overview)
                    .font(.appFont(metaSize))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(3)
                    .frame(maxWidth: copyWidth, alignment: .leading)
            }
            if collapsed {
                #if os(tvOS)
                // A slim focus target lets Up from the rows return to the hero.
                Color.clear.frame(height: 1).focusable().focused($focusedAction, equals: .play)
                #endif
            } else {
                actions(for: item)
            }
        }
        .frame(maxWidth: copyWidth, alignment: .leading)
        .id(item.id)
        .transition(.opacity)
    }

    @ViewBuilder
    private func titleArt(for item: CatalogItem) -> some View {
        if showLogo, let logo = logos[item.id] {
            CachedAsyncImage(url: logo, maxPixel: 1200) { image in
                image.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                titleText(item)
            }
            .frame(maxWidth: logoWidth, maxHeight: logoHeight, alignment: .bottomLeading)
            .accessibilityLabel(item.title)
        } else {
            titleText(item)
        }
    }

    private func titleText(_ item: CatalogItem) -> some View {
        Text(item.title)
            .font(.appFont(collapsed ? titleSize * 0.7 : titleSize, weight: .bold, design: .serif))
            .foregroundStyle(.white)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .accessibilityAddTraits(.isHeader)
    }

    private func actions(for item: CatalogItem) -> some View {
        HStack(spacing: 18) {
            Button { onPlay(item) } label: {
                Label(item.isSeries ? "Watch" : "Play", systemImage: "play.fill")
                    .font(.appFont(buttonSize, weight: .bold))
                    .padding(.horizontal, 10)
            }
            .buttonStyle(OmniHeroButtonStyle(prominent: true))
            .focused($focusedAction, equals: .play)

            Button { onOpen(item) } label: {
                Label("Details", systemImage: "info.circle")
                    .font(.appFont(buttonSize, weight: .semibold))
            }
            .buttonStyle(OmniHeroButtonStyle(prominent: false))
            .focused($focusedAction, equals: .info)

            Button {
                library.add(item.asLibraryItem())
                ToastCenter.shared.show("Added to Library")
            } label: {
                Image(systemName: "plus")
                    .font(.appFont(buttonSize, weight: .bold))
            }
            .buttonStyle(OmniHeroButtonStyle(prominent: false))
            .focused($focusedAction, equals: .add)
            .accessibilityLabel("Add to Library")
        }
        .omniFocusSection()
    }

    private var indicators: some View {
        HStack(spacing: 8) {
            ForEach(items.indices, id: \.self) { i in
                Capsule()
                    .fill(.white.opacity(i == index ? 1 : 0.35))
                    .frame(width: i == index ? 22 : 8, height: 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, OmniStyle.edge)
        .padding(.bottom, bottomInset)
        .animation(.easeOut(duration: 0.2), value: index)
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        LinearGradient(colors: [Theme.Colors.backgroundElevated, .black], startPoint: .top, endPoint: .bottom)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Nova")
                        .font(.appFont(titleSize, weight: .bold, design: .serif))
                    Text("Add catalogs in Settings › Sources to fill Home.")
                        .font(.appFont(metaSize))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .foregroundStyle(.white)
                .padding(OmniStyle.edge)
            }
    }

    // MARK: Behavior

    private func metadata(for item: CatalogItem) -> String {
        var parts: [String] = []
        if let year = item.year { parts.append(String(year)) }
        parts.append(item.isSeries ? "Series" : "Movie")
        parts.append(contentsOf: item.genres.prefix(2))
        if let rating = item.rating, rating > 0 { parts.append("★ " + rating.formatted(.number.precision(.fractionLength(1)))) }
        return parts.joined(separator: " · ")
    }

    private func loadLogo(for item: CatalogItem?) async {
        guard showLogo, let item, logos[item.id] == nil else { return }
        guard let url = try? await env.tmdb.titleLogoURL(for: item.contentID), !Task.isCancelled else { return }
        logos[item.id] = url
    }

    private struct RotationKey: Hashable { let ids: [String]; let index: Int; let canRotate: Bool }

    private var rotationKey: RotationKey {
        RotationKey(ids: items.map(\.id), index: index,
                    canRotate: autoAdvance && isActive && !collapsed && !reduceMotion && !voiceOver
                        && focusedAction == nil && scenePhase == .active)
    }

    private func rotate() async {
        guard rotationKey.canRotate, items.count > 1 else { return }
        // Warm the next backdrop so the crossfade lands on a decoded image.
        let next = items[(index + 1) % items.count]
        ImageLoader.shared.prefetch([next.backdropURL ?? next.posterURL].compactMap { $0 }, maxPixel: 1920)
        do { try await Task.sleep(for: .seconds(10)) } catch { return }
        guard !Task.isCancelled, rotationKey.canRotate else { return }
        index = (index + 1) % items.count
    }

    #if os(iOS)
    private func swipe(_ value: DragGesture.Value) {
        guard items.count > 1 else { return }
        if value.translation.width < -40 { index = (index + 1) % items.count }
        else if value.translation.width > 40 { index = (index - 1 + items.count) % items.count }
    }
    #endif

    // MARK: Metrics

    #if os(tvOS)
    private let titleSize: CGFloat = 76
    private let metaSize: CGFloat = 24
    private let buttonSize: CGFloat = 24
    private let copyWidth: CGFloat = 880
    private var logoWidth: CGFloat { collapsed ? 420 : 640 }
    private var logoHeight: CGFloat { collapsed ? 120 : 220 }
    private let bottomInset: CGFloat = 70
    #else
    private var titleSize: CGFloat { Theme.isPad ? 52 : 36 }
    private var metaSize: CGFloat { Theme.isPad ? 17 : 14 }
    private var buttonSize: CGFloat { Theme.isPad ? 17 : 15 }
    private var copyWidth: CGFloat { Theme.isPad ? 560 : 520 }
    private var logoWidth: CGFloat { Theme.isPad ? 420 : 260 }
    private var logoHeight: CGFloat { Theme.isPad ? 150 : 100 }
    private var bottomInset: CGFloat { Theme.isPad ? 36 : 22 }
    #endif
}

/// Hero buttons: white pill for the primary action, translucent for the rest.
/// On tvOS focus inverts secondary buttons to white like system controls.
struct OmniHeroButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        HeroButtonBody(configuration: configuration, prominent: prominent)
    }

    private struct HeroButtonBody: View {
        let configuration: Configuration
        let prominent: Bool
        @Environment(\.isFocused) private var focused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var filled: Bool {
            #if os(tvOS)
            focused
            #else
            prominent
            #endif
        }

        var body: some View {
            configuration.label
                .foregroundStyle(filled ? Color.black : Color.white)
                .padding(.horizontal, padH)
                .frame(minHeight: height)
                .background(Capsule().fill(filled ? Color.white : Color.white.opacity(0.18)))
                .scaleEffect(configuration.isPressed ? 0.96 : (focused && !reduceMotion ? 1.06 : 1))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: focused)
        }

        #if os(tvOS)
        private let height: CGFloat = 66
        private let padH: CGFloat = 30
        #else
        private var height: CGFloat { 44 }
        private var padH: CGFloat { 18 }
        #endif
    }
}

// MARK: - Continue Watching

struct OmniContinueWatchingRow: View {
    let items: [MediaItem]
    var onPlay: (MediaItem) -> Void
    var onRestart: (MediaItem) -> Void
    var onRemove: (MediaItem) -> Void
    /// Called when a card gains focus (tvOS), so Home can collapse its hero.
    var onFocusCard: (() -> Void)? = nil

    @AppStorage(OmniLayoutKey.smallContinueWatching) private var small = false
    @AppStorage(OmniLayoutKey.posterSize) private var posterSizeRaw = OmniPosterSize.medium.rawValue

    private var width: CGFloat {
        let size = small ? .small : (OmniPosterSize(rawValue: posterSizeRaw) ?? .medium)
        return OmniStyle.landscapeWidth(size)
    }

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                OmniRowHeader(title: "Continue Watching")
                    .accessibilityIdentifier("home.continue-watching.heading")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: OmniStyle.cardSpacing) {
                        ForEach(items) { item in
                            Button { onPlay(item) } label: { card(item) }
                                .buttonStyle(OmniCardButtonStyle())
                                .onFocusChange { if $0 { onFocusCard?() } }
                                .accessibilityIdentifier("home.continue-watching.\(item.id.uuidString)")
                                .contextMenu {
                                    Button { onPlay(item) } label: {
                                        Label(item.hasResumePoint ? "Resume" : "Play", systemImage: "play.fill")
                                    }
                                    Button { onRestart(item) } label: { Label("Start Over", systemImage: "gobackward") }
                                    Button(role: .destructive) { onRemove(item) } label: {
                                        Label("Remove from Continue Watching", systemImage: "xmark.circle")
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, OmniStyle.edge)
                    .padding(.vertical, 18)
                }
                .scrollClipDisabled()
                .accessibilityIdentifier("home.continue-watching.rail")
            }
        }
    }

    private func card(_ item: MediaItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                CachedAsyncImage(url: item.backdropURL ?? item.posterURL, maxPixel: 960) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Theme.Colors.card.overlay {
                        Image(systemName: item.isSeries ? "tv" : "film")
                            .font(.system(size: width * 0.1, weight: .light))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .frame(width: width, height: width * 9 / 16)
                .clipped()

                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                if item.hasResumePoint {
                    GeometryReader { geo in
                        Capsule().fill(.white.opacity(0.3))
                            .overlay(alignment: .leading) {
                                Capsule().fill(AccentManager.fallback)
                                    .frame(width: max(4, geo.size.width * item.progressFraction))
                            }
                    }
                    .frame(height: 5)
                    .padding(12)
                }
            }
            .frame(width: width, height: width * 9 / 16)
            .clipShape(RoundedRectangle(cornerRadius: OmniStyle.cardRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.seriesTitle ?? item.title)
                    .font(.appFont(titleSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let caption = caption(item) {
                    Text(caption)
                        .font(.appFont(titleSize * 0.8))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .frame(width: width, alignment: .leading)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([item.displayTitle, remaining(item)].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint("Plays from where you left off")
    }

    private func caption(_ item: MediaItem) -> String? {
        if let episode = item.episode { return episode.label + (remaining(item).map { " · \($0)" } ?? "") }
        return remaining(item)
    }

    private func remaining(_ item: MediaItem) -> String? {
        guard item.hasResumePoint, let duration = item.duration, duration.isFinite,
              duration > item.lastPlayedPosition else { return nil }
        let minutes = max(1, ((duration - item.lastPlayedPosition) / 60).rounded())
        return "\(minutes.formatted(.number.precision(.fractionLength(0)))) min left"
    }

    private var titleSize: CGFloat {
        #if os(tvOS)
        22
        #else
        Theme.isPad ? 15 : 13
        #endif
    }
}
