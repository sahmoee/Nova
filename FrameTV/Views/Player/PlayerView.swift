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

    init(item: MediaItem, series: CatalogItem? = nil) {
        self.item = item
        self.series = series
        _model = StateObject(wrappedValue: PlayerModel(item: item))
    }

    var body: some View {
        Group {
            #if os(iOS)
            if settings.useExternalPlayer {
                // Hand the stream to the chosen external app, then dismiss.
                externalHandoffBody
            } else {
                inAppBody
            }
            #else
            inAppBody
            #endif
        }
    }

    @ViewBuilder
    private var inAppBody: some View {
        // AVPlayer can only open MP4/M4V/MOV/HLS. For anything else (MKV, AVI,
        // WebM, or unknown), use the VLC-backed player which handles all formats.
        // The user's preferred built-in player can force one engine.
        if PlaybackEngineRouter.shouldUseVLC(for: item, preference: settings.builtInPlayer) {
            VLCPlayerView(item: item, series: series)
        } else {
            avPlayerBody
        }
    }

    #if os(iOS)
    @State private var handoffFailed = false

    @ViewBuilder
    private var externalHandoffBody: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: Theme.Spacing.lg) {
                if handoffFailed {
                    ErrorStateView(
                        title: "\(settings.preferredExternalPlayer.title) isn't available",
                        message: "Install it, or turn off external playback in Settings to play in FrameTV.",
                        onBack: { dismiss() }
                    )
                } else {
                    ProgressView().tint(.white)
                    Text("Opening in \(settings.preferredExternalPlayer.title)…")
                        .font(.appFont(20)).foregroundStyle(.white)
                }
            }
        }
        .onAppear {
            let ok = settings.preferredExternalPlayer.open(item.playbackURL)
            if ok {
                // Mark progress as played and leave the player screen.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { dismiss() }
            } else {
                handoffFailed = true
            }
        }
    }
    #endif

    private var avPlayerBody: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch model.state {
            case .loading:
                LoadingView(message: "Preparing playback…")
            case .ready:
                // Native AVPlayerViewController UI: scrubbing, subtitle/audio menus,
                // fullscreen toggle, Picture in Picture, and AirPlay. In fullscreen the
                // system hides all chrome automatically.
                AVPlayerContainer(player: model.player, onExitFullscreen: { dismiss() })
                    .ignoresSafeArea()
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
        #if os(iOS)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(true)
        #endif
        .onChange(of: model.didFinish) { _, finished in
            if finished { handleFinish() }
        }
        .navigationDestination(item: $navigateNext) { next in
            PlayerView(item: next, series: series)
        }
    }

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
            // No auto-play and no overlay prompt with native controls: just exit.
            dismiss()
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

/// A player surface using AVPlayerViewController with its full native UI: transport
/// bar, scrubbing, subtitle and audio menus, Picture in Picture, AirPlay, and the
/// fullscreen toggle. On iOS it enters fullscreen automatically when playback begins.
struct AVPlayerContainer: UIViewControllerRepresentable {
    let player: AVPlayer
    /// Called when the user exits fullscreen so the presenting view can dismiss.
    var onExitFullscreen: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(onExitFullscreen: onExitFullscreen) }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.delegate = context.coordinator
        // Native transport UI (scrub bar, subtitle/audio menu, fullscreen button).
        vc.showsPlaybackControls = true
        vc.allowsPictureInPicturePlayback = true
        vc.canStartPictureInPictureAutomaticallyFromInline = true
        #if os(iOS)
        vc.videoGravity = .resizeAspect
        vc.entersFullScreenWhenPlaybackBegins = true
        vc.exitsFullScreenWhenPlaybackEnds = false
        vc.updatesNowPlayingInfoCenter = true
        #endif
        #if os(tvOS)
        vc.playbackControlsIncludeInfoViews = true
        vc.playbackControlsIncludeTransportBar = true
        #endif
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        let onExitFullscreen: (() -> Void)?
        init(onExitFullscreen: (() -> Void)?) { self.onExitFullscreen = onExitFullscreen }

        #if os(iOS)
        // Called when the user taps the exit-fullscreen (minimize) control.
        func playerViewController(_ playerViewController: AVPlayerViewController,
                                  willEndFullScreenPresentationWithAnimationCoordinator
                                  coordinator: UIViewControllerTransitionCoordinator) {
            coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                self?.onExitFullscreen?()
            }
        }
        #endif
    }
}
