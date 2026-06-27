//
//  PlayerView.swift
//  FrameTV
//
//  The player surface. Wraps the AVPlayer in a tvOS-friendly container and
//  overlays Skip Intro / Skip Outro / Next Episode / Subtitles controls. Drives
//  auto-play-next by asking the environment for the next episode when one finishes.
//

import SwiftUI
import AVKit

struct PlayerView: View {
    let item: MediaItem
    /// Optional context so the player can compute and play the next episode.
    var series: CatalogItem?

    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var progress: PlaybackProgressStore
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @StateObject private var model: PlayerModel
    @State private var preparedNext: MediaItem?      // pre-resolved, not yet navigated
    @State private var navigateNext: MediaItem?      // bound to navigationDestination
    @State private var prepareTask: Task<Void, Never>?
    @State private var showNextPrompt = false

    init(item: MediaItem, series: CatalogItem? = nil) {
        self.item = item
        self.series = series
        _model = StateObject(wrappedValue: PlayerModel(item: item))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch model.state {
            case .loading:
                LoadingView(message: "Preparing playback…")
            case .ready:
                AVPlayerContainer(player: model.player)
                    .ignoresSafeArea()
                overlay
            case .failed(let message):
                ErrorStateView(
                    title: "Playback failed",
                    message: message,
                    retryTitle: "Retry",
                    onRetry: { model.retry() },
                    onBack: { dismiss() }
                )
            }
        }
        .onAppear {
            model.configure(progressStore: progress,
                            settings: settings,
                            trakt: env.trakt,
                            openSubtitles: env.openSubtitles)
            model.start()
            prepareNextEpisode()
        }
        .onDisappear { model.stopAndSave(); prepareTask?.cancel() }
        .onChange(of: model.didFinish) { _, finished in
            if finished { handleFinish() }
        }
        .sheet(isPresented: $model.showSubtitlePicker) {
            SubtitlePickerView(
                tracks: model.availableSubtitles,
                selectedID: model.selectedSubtitleID,
                onSelect: { model.selectSubtitle($0) }
            )
        }
        .navigationDestination(item: $navigateNext) { next in
            PlayerView(item: next, series: series)
        }
    }

    // MARK: - Overlay

    @ViewBuilder
    private var overlay: some View {
        VStack {
            // Top-right transport affordances.
            HStack {
                Spacer()
                if !model.availableSubtitles.isEmpty {
                    overlayButton(systemImage: "captions.bubble",
                                  label: "Subtitles") { model.showSubtitlePicker = true }
                }
            }
            .padding(Theme.Spacing.lg)

            Spacer()

            // Bottom-right skip / next controls.
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: Theme.Spacing.sm) {
                    if let skip = model.activeSkip {
                        skipButton(skip)
                    }
                    if showNextPrompt, preparedNext != nil {
                        nextEpisodeButton
                    }
                }
            }
            .padding(Theme.Spacing.xl)
        }
    }

    private func overlayButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .font(.appFont(22, weight: .semibold))
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(.ultraThinMaterial, in: Capsule())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private func skipButton(_ skip: SkipSegment) -> some View {
        Button { model.performSkip(skip) } label: {
            Label(skip.kind.label, systemImage: "forward.end.fill")
                .font(.appFont(24, weight: .bold))
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
                .background(Theme.Colors.accent, in: Capsule())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private var nextEpisodeButton: some View {
        Button { playNext() } label: {
            Label("Next Episode", systemImage: "play.fill")
                .font(.appFont(24, weight: .bold))
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
                .background(Theme.Colors.accentSecondary, in: Capsule())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    // MARK: - Next episode

    /// Pre-resolves the next episode's playable item so the Next button is instant.
    /// Done regardless of the auto-play setting (the setting only controls whether
    /// it plays automatically vs. shows a button).
    private func prepareNextEpisode() {
        guard let series, let epRef = item.episode else { return }
        guard let nextEp = env.catalog.nextEpisode(after: epRef, in: series) else { return }

        prepareTask?.cancel()
        prepareTask = Task {
            // Find streams for the next episode and resolve the best one.
            let streams = await env.catalog.streams(
                for: series.contentID,
                episode: EpisodeRef(season: nextEp.season, number: nextEp.number),
                preferredQuality: settings.preferredStreamQuality
            )
            if Task.isCancelled { return }
            guard let best = StreamRanker.autoSelect(
                streams,
                preferredQuality: settings.preferredStreamQuality,
                requireCached: settings.requireCachedStreams
            ) else { return }

            if let playable = try? await env.catalog.makePlayable(
                stream: best, catalog: series, episode: nextEp
            ) {
                if Task.isCancelled { return }
                await MainActor.run { self.preparedNext = playable }
            }
        }
    }

    private func handleFinish() {
        guard preparedNext != nil else {
            // No next episode: leave the player.
            dismiss()
            return
        }
        if settings.autoPlayNext {
            playNext()
        } else {
            withAnimation { showNextPrompt = true }
        }
    }

    private func playNext() {
        guard let next = preparedNext else { return }
        // Add to library so it shows in Continue Watching, then navigate.
        env.library.add(next)
        model.stopAndSave()
        navigateNext = next
    }
}

// MARK: - AVPlayerViewController bridge

/// A tvOS-friendly player surface using AVPlayerViewController so we get the
/// native transport bar, info panel, and subtitle/audio menus, while still being
/// able to overlay our own SwiftUI controls on top.
struct AVPlayerContainer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.allowsPictureInPicturePlayback = true
        #if os(tvOS)
        vc.playbackControlsIncludeInfoViews = true
        #endif
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }
}
