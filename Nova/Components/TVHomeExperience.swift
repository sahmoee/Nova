//
//  TVHomeExperience.swift
//  Nova
//
//  The Apple TV Home composition: edge-to-edge artwork, a quiet action row,
//  and landscape Continue Watching cards. iPhone and iPad keep their own layout.
//

#if os(tvOS)
import SwiftUI

struct TVHomeHeroCarousel: View {
    let items: [MediaItem]
    let height: CGFloat
    let autoAdvance: Bool
    let isActive: Bool
    let reduceArtworkMotion: Bool
    let playFocusNamespace: Namespace.ID
    var onPlay: (MediaItem) -> Void
    var onOpen: (MediaItem) -> Void

    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @FocusState private var focusedAction: Action?
    @State private var selectedID: UUID?
    @State private var details: CatalogItem?
    @State private var detailContentKey: String?
    @State private var titleLogoURL: URL?
    @State private var logoContentKey: String?

    private enum Action: Hashable { case play, queue, info }

    // Selection follows media identity when history or queue ordering changes.
    private var currentItem: MediaItem? {
        items.first(where: { $0.id == selectedID }) ?? items.first
    }

    private var reduceMotion: Bool { reduceArtworkMotion || systemReduceMotion }

    private var currentDetails: CatalogItem? {
        detailContentKey == currentItem?.contentKey ? details : nil
    }

    private struct RotationState: Hashable {
        let itemIDs: [UUID]
        let selectedID: UUID?
        let canAdvance: Bool
    }

    private var rotationState: RotationState {
        RotationState(itemIDs: items.map(\.id), selectedID: currentItem?.id,
                      canAdvance: isActive && autoAdvance && !reduceMotion && !voiceOverEnabled
                          && focusedAction == nil && scenePhase == .active)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                Color.black
                if let item = currentItem {
                    artwork(for: item, width: geometry.size.width)
                        .accessibilityHidden(true)

                    heroCopy(for: item, width: geometry.size.width)
                        .padding(.leading, TVReferenceStyle.edge)
                        .padding(.bottom, 110)

                    pageIndicators
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 25)
                } else {
                    emptyHero
                        .padding(.horizontal, TVReferenceStyle.edge)
                        .padding(.bottom, 90)
                }
            }
            .frame(width: geometry.size.width, height: height)
        }
        .frame(height: height)
        .task(id: currentItem?.contentKey) {
            // Hydration may finish after selection changes. Cancellation prevents a
            // late overview from appearing on a different title.
            details = nil
            guard let item = currentItem else { return }
            let hydrated = await env.catalog.hydrate(item.asCatalogItem())
            guard !Task.isCancelled, currentItem?.contentKey == item.contentKey else { return }
            detailContentKey = item.contentKey
            details = hydrated
        }
        .task(id: currentItem?.contentKey) {
            titleLogoURL = nil
            guard let item = currentItem, let contentID = item.contentID else { return }
            let logo = try? await env.tmdb.titleLogoURL(for: contentID)
            guard !Task.isCancelled, currentItem?.contentKey == item.contentKey else { return }
            logoContentKey = item.contentKey
            titleLogoURL = logo
        }
        // Root tabs remain mounted to preserve scroll and focus. Visibility must
        // therefore cancel the timer explicitly instead of relying on disappear.
        .task(id: rotationState) {
            guard rotationState.canAdvance, items.count > 1 else { return }
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            guard !Task.isCancelled, rotationState.canAdvance else { return }
            advance()
        }
        .onAppear {
            if selectedID == nil { selectedID = items.first?.id }
        }
        .onChange(of: items.map(\.id)) { _, ids in
            guard let selectedID, ids.contains(selectedID) else {
                self.selectedID = ids.first
                return
            }
        }
    }

    private func artwork(for item: MediaItem, width: CGFloat) -> some View {
        ZStack {
            CachedAsyncImage(url: item.backdropURL ?? item.posterURL, maxPixel: 2560) { image in
                ZStack {
                    // A restrained bleed fills odd aspect ratios. The foreground
                    // preserves the complete source composition and is never stretched.
                    image.resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: width, height: height)
                        .blur(radius: 24)
                        .opacity(0.48)
                    image.resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: width, height: height, alignment: .topTrailing)
                }
            } placeholder: {
                Color(white: 0.055)
            }
            .id(item.backdropURL ?? item.posterURL)
            .transition(.opacity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: item.id)

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.62), location: 0),
                    .init(color: .black.opacity(0.32), location: 0.27),
                    .init(color: .clear, location: 0.66)
                ],
                startPoint: .leading, endPoint: .trailing
            )
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.32),
                    .init(color: .black.opacity(0.12), location: 0.52),
                    .init(color: .black.opacity(0.68), location: 0.80),
                    .init(color: .black, location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
        .frame(width: width, height: height)
        .clipped()
        .allowsHitTesting(false)
    }

    private func heroCopy(for item: MediaItem, width: CGFloat) -> some View {
        let copyWidth = min(width * 0.44, 790)
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 15) {
                titleArtwork(for: item, width: copyWidth)

                Text(metadata(for: item))
                    .font(.appFont(23, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if let overview = currentDetails?.overview?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !overview.isEmpty {
                    Text(overview)
                        .font(.appFont(23))
                        .foregroundStyle(.white.opacity(0.76))
                        .lineLimit(2)
                        .lineSpacing(4)
                        .frame(maxWidth: copyWidth, alignment: .leading)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("home.hero.summary")

            // These controls retain identity as the selected title changes, keeping
            // remote focus on the same action while the hero rotates.
            HStack(spacing: 14) {
                Button { onPlay(item) } label: {
                    Label(item.hasResumePoint ? "Resume" : "Play", systemImage: "play.fill")
                        .font(.appFont(26, weight: .semibold))
                        .padding(.horizontal, 28)
                        .frame(height: TVReferenceStyle.controlHeight)
                }
                .accessibilityIdentifier("home.hero.play")
                .focused($focusedAction, equals: .play)
                .prefersDefaultFocus(true, in: playFocusNamespace)
                .accessibilityLabel("\(item.hasResumePoint ? "Resume" : "Play") \(item.displayTitle)")
                .buttonStyle(TVReferenceButtonStyle(selected: true, cornerRadius: 28))

                Button { toggleQueue(item) } label: {
                    Image(systemName: library.isQueued(item) ? "checkmark" : "plus")
                        .font(.appFont(27, weight: .medium))
                        .frame(width: TVReferenceStyle.controlHeight, height: TVReferenceStyle.controlHeight)
                }
                .accessibilityIdentifier("home.hero.queue")
                .focused($focusedAction, equals: .queue)
                .accessibilityLabel(library.isQueued(item) ? "Remove from Up Next" : "Add to Up Next")
                .buttonStyle(TVReferenceButtonStyle(cornerRadius: 28))

                Button { onOpen(item) } label: {
                    Image(systemName: "info.circle")
                        .font(.appFont(28, weight: .medium))
                        .frame(width: TVReferenceStyle.controlHeight, height: TVReferenceStyle.controlHeight)
                }
                .accessibilityIdentifier("home.hero.info")
                .focused($focusedAction, equals: .info)
                .accessibilityLabel("More information about \(item.displayTitle)")
                .buttonStyle(TVReferenceButtonStyle(cornerRadius: 28))
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: copyWidth, alignment: .leading)
    }

    private func titleArtwork(for item: MediaItem, width: CGFloat) -> some View {
        Group {
            if logoContentKey == item.contentKey, let titleLogoURL {
                CachedAsyncImage(url: titleLogoURL, maxPixel: 1200) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                        .frame(width: min(width, 660), height: 160, alignment: .bottomLeading)
                } placeholder: {
                    titleText(for: item)
                }
                .id(titleLogoURL)
            } else {
                titleText(for: item)
            }
        }
        .frame(width: width, height: 160, alignment: .bottomLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.seriesTitle ?? item.title)
    }

    private func titleText(for item: MediaItem) -> some View {
        Text(item.seriesTitle ?? item.title)
            .font(.appFont(64, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(2)
            .minimumScaleFactor(0.65)
            .shadow(color: .black.opacity(0.28), radius: 12, y: 2)
    }

    @ViewBuilder private var pageIndicators: some View {
        if items.count > 1 {
            HStack(spacing: 11) {
                ForEach(items) { item in
                    Circle()
                        .fill(.white.opacity(item.id == currentItem?.id ? 0.96 : 0.34))
                        .frame(width: item.id == currentItem?.id ? 9 : 7,
                               height: item.id == currentItem?.id ? 9 : 7)
                }
            }
            .accessibilityHidden(true)
        }
    }

    private var emptyHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Your personal media hub")
                .font(.appFont(58, weight: .bold))
                .foregroundStyle(.white)
            Text("Start watching a movie or show to see it featured here.")
                .font(.appFont(24))
                .foregroundStyle(.white.opacity(0.65))
        }
    }

    private func metadata(for item: MediaItem) -> String {
        var values = [item.sourceType == .liveTV ? "Live TV" : (item.isSeries ? "Series" : "Movie")]
        if let genres = currentDetails?.genres, !genres.isEmpty {
            values.append(contentsOf: genres.prefix(2))
        } else if !item.subtitleLine.isEmpty {
            values.append(item.subtitleLine)
        }
        return values.joined(separator: " · ")
    }

    private func toggleQueue(_ item: MediaItem) {
        if library.isQueued(item) {
            library.removeFromQueue(item)
            ToastCenter.shared.show("Removed from Up Next")
        } else {
            library.addToQueue(item)
            ToastCenter.shared.show("Added to Up Next")
        }
    }

    private func advance() {
        guard isActive, items.count > 1 else { return }
        let index = items.firstIndex(where: { $0.id == currentItem?.id }) ?? 0
        selectedID = items[(index + 1) % items.count].id
    }
}

struct TVContinueWatchingRail: View {
    let items: [MediaItem]
    let availableWidth: CGFloat
    var onPlay: (MediaItem) -> Void
    var onRestart: (MediaItem) -> Void
    var onRemove: (MediaItem) -> Void

    // Four complete landscape cards and a glimpse of the next match the TV reference.
    private var cardWidth: CGFloat {
        max(280, (availableWidth - TVReferenceStyle.edge * 2 - 28 * 3.25) / 4.25)
    }

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 15) {
                Text("Continue Watching")
                    .accessibilityIdentifier("home.continue-watching.heading")
                    .font(.appFont(32, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, TVReferenceStyle.edge)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 28) {
                        ForEach(items) { item in
                            TVContinueWatchingCard(item: item, width: cardWidth,
                                                   onPlay: { onPlay(item) },
                                                   onRestart: { onRestart(item) },
                                                   onRemove: { onRemove(item) })
                        }
                    }
                    .padding(.horizontal, TVReferenceStyle.edge)
                    .padding(.vertical, 8)
                }
                .scrollClipDisabled()
                .accessibilityIdentifier("home.continue-watching.rail")
            }
        }
    }
}

private struct TVContinueWatchingCard: View {
    let item: MediaItem
    let width: CGFloat
    var onPlay: () -> Void
    var onRestart: () -> Void
    var onRemove: () -> Void

    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onPlay) {
            VStack(alignment: .leading, spacing: 11) {
                ZStack(alignment: .bottomLeading) {
                    CachedAsyncImage(url: item.backdropURL ?? item.posterURL, maxPixel: 960) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color(white: 0.10)
                            .overlay {
                                Image(systemName: item.isSeries ? "tv" : "film")
                                    .font(.appFont(40, weight: .light))
                                    .foregroundStyle(.white.opacity(0.32))
                            }
                    }
                    .frame(width: width, height: width * 9 / 16)
                    .clipped()

                    if item.hasResumePoint {
                        LinearGradient(colors: [.clear, .black.opacity(0.48)],
                                       startPoint: .center, endPoint: .bottom)
                        Capsule()
                            .fill(.white.opacity(0.28))
                            .frame(height: 4)
                            .overlay(alignment: .leading) {
                                Capsule().fill(.white)
                                    .frame(width: max(4, (width - 28) * item.progressFraction), height: 4)
                            }
                            .padding(14)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: TVReferenceStyle.cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: TVReferenceStyle.cornerRadius)
                        .strokeBorder(.white.opacity(focused ? 1 : 0.08), lineWidth: focused ? 4 : 1)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.seriesTitle ?? item.title)
                        .font(.appFont(23, weight: .medium))
                        .foregroundStyle(.white.opacity(focused ? 1 : 0.82))
                        .lineLimit(1)
                    if let caption {
                        Text(caption)
                            .font(.appFont(19))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
            }
            .frame(width: width, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: TVReferenceStyle.cornerRadius))
        }
        .buttonStyle(.plain)
        .focused($focused)
        .scaleEffect(focused && !reduceMotion ? 1.035 : 1, anchor: .top)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: focused)
        .accessibilityIdentifier("home.continue-watching.\(item.id.uuidString)")
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("Press to play. Hold for more options.")
        .contextMenu {
            Button(action: onPlay) {
                Label(item.hasResumePoint ? "Resume" : "Play", systemImage: "play.fill")
            }
            Button(action: onRestart) {
                Label("Start Over", systemImage: "gobackward")
            }
            Button(role: .destructive, action: onRemove) {
                Label("Remove from Continue Watching", systemImage: "xmark.circle")
            }
        }
    }

    private var caption: String? {
        if let episode = item.episode { return episode.label + (remainingTime.map { " · \($0)" } ?? "") }
        return remainingTime ?? (item.subtitleLine.isEmpty ? nil : item.subtitleLine)
    }

    private var remainingTime: String? {
        guard item.hasResumePoint, let duration = item.duration, duration.isFinite,
              duration > item.lastPlayedPosition else { return nil }
        let minutes = max(1, ((duration - item.lastPlayedPosition) / 60).rounded())
        return "\(minutes.formatted(.number.precision(.fractionLength(0)))) min left"
    }

    private var accessibilityDescription: String {
        [item.displayTitle, remainingTime].compactMap { $0 }.joined(separator: ", ")
    }
}
#endif
