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
#if canImport(UIKit)
import UIKit
#endif

struct PlayerView: View {
    let item: MediaItem
    /// Optional context so the player can compute and play the next episode.
    var series: CatalogItem?

    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var progress: PlaybackProgressStore
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @StateObject private var model: PlayerModel
    @ObservedObject private var sleepTimer = SleepTimer.shared
    @State private var preparedNext: MediaItem?      // pre-resolved, not yet navigated
    @State private var navigateNext: MediaItem?      // bound to navigationDestination
    @State private var prepareTask: Task<Void, Never>?

    // Resume-or-restart prompt state.
    @State private var resumePromptPosition: TimeInterval?
    @State private var didChooseResume = false

    // One-tap recovery: when set, forces a specific engine for this session,
    // overriding the automatic/preference routing (used by "Try other player").
    @State private var engineOverride: PlaybackEngine?

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
        .overlay {
            if let pos = resumePromptPosition {
                resumeRestartPrompt(position: pos)
            }
        }
        .overlay {
            // Night mode: a gentle dark veil over the video to ease late viewing.
            // Doesn't intercept taps/focus so playback controls still work.
            if settings.nightMode {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            // Sleep timer: pause playback after a chosen interval. A tap target
            // overlaid on the system player is safe (only custom gestures conflict).
            Menu {
                ForEach(SleepTimer.Preset.allCases) { preset in
                    Button(preset.label) { sleepTimer.start(minutes: preset.rawValue) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: sleepTimer.isRunning ? "moon.fill" : "moon")
                    if sleepTimer.isRunning {
                        Text(sleepTimer.display)
                            .font(.appFont(14, weight: .semibold)).monospacedDigit()
                    }
                }
                .font(.appFont(18, weight: .semibold))
                .foregroundStyle(sleepTimer.isRunning ? Theme.Colors.accent : .white.opacity(0.85))
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .padding(.top, Theme.Spacing.xl)
            .padding(.trailing, Theme.Spacing.lg)
        }
        .onAppear {
            SleepTimer.shared.onFire = { [weak model] in model?.pause() }
            if settings.autoSleepMinutes > 0, !SleepTimer.shared.isRunning {
                SleepTimer.shared.start(minutes: settings.autoSleepMinutes)
            }
        }
        .onDisappear {
            SleepTimer.shared.cancel()
            SleepTimer.shared.onFire = nil
        }
    }

    /// Asks the user whether to resume from their saved position or start over.
    private func resumeRestartPrompt(position: TimeInterval) -> some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: Theme.Spacing.lg) {
                Image(systemName: "play.circle")
                    .font(.appFont(56, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
                Text(item.title)
                    .font(.appFont(28, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("You left off at \(timeLabel(position)).")
                    .font(.appFont(20))
                    .foregroundStyle(Theme.Colors.textSecondary)

                VStack(spacing: Theme.Spacing.sm) {
                    FocusableButton(title: "Resume from \(timeLabel(position))",
                                    systemImage: "play.fill", prominent: true) {
                        didChooseResume = true
                        resumePromptPosition = nil
                        model.forceRestart = false
                        model.start()
                        prepareNextEpisode()
                    }
                    .frame(maxWidth: 420)

                    FocusableButton(title: "Start from beginning",
                                    systemImage: "backward.end.fill") {
                        didChooseResume = true
                        resumePromptPosition = nil
                        model.forceRestart = true
                        model.start()
                        prepareNextEpisode()
                    }
                    .frame(maxWidth: 420)

                    FocusableButton(title: "Cancel", systemImage: "xmark") {
                        resumePromptPosition = nil
                        dismiss()
                    }
                    .frame(maxWidth: 420)
                }
            }
            .padding(Theme.Spacing.xl)
        }
    }

    private func timeLabel(_ t: TimeInterval) -> String {
        let total = Int(t)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }

    /// Smart recovery when playback fails: classifies the failure, suggests the most
    /// likely fix first (other engine vs. different stream), and offers one-tap retry,
    /// switching engine, opening externally, or going back to pick another stream.
    private func playbackRecovery(message: String) -> some View {
        let reason = PlaybackFailureReason.classify(message)
        // This engine failed for this title — clear the remembered choice so the app
        // doesn't keep routing here next time.
        PlayerMemory.forget(for: item)

        return ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
            VStack(spacing: Theme.Spacing.lg) {
                Image(systemName: reason.systemImage)
                    .font(.appFont(52, weight: .semibold))
                    .foregroundStyle(Theme.Colors.error)
                Text("Playback failed")
                    .font(.appFont(28, weight: .bold))
                    .foregroundStyle(.white)
                Text(reason.message)
                    .font(.appFont(19))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 640)

                VStack(spacing: Theme.Spacing.sm) {
                    // Try the other engine — surfaced first when a codec/engine issue.
                    // Setting the override re-routes the view to the other player, which
                    // builds a fresh model; no need to restart the failed one.
                    FocusableButton(title: "Try \(useVLCEngine ? "Apple Player" : "VLC Player")",
                                    systemImage: "arrow.triangle.2.circlepath",
                                    prominent: reason.suggestsOtherEngine) {
                        engineOverride = useVLCEngine ? .avPlayer : .vlc
                    }
                    .frame(maxWidth: 460)

                    // Retry the same stream/engine.
                    FocusableButton(title: "Retry", systemImage: "gobackward") {
                        model.retry()
                    }
                    .frame(maxWidth: 460)

                    #if os(iOS)
                    FocusableButton(title: "Open in \(settings.preferredExternalPlayer.title)",
                                    systemImage: "arrow.up.forward.app") {
                        _ = settings.preferredExternalPlayer.open(item.playbackURL)
                    }
                    .frame(maxWidth: 460)
                    #endif

                    // Go back to pick a different stream — surfaced first when the
                    // issue is the stream itself (expired/timeout/no-stream).
                    FocusableButton(title: "Choose a different stream",
                                    systemImage: "list.bullet",
                                    prominent: reason.suggestsDifferentStream) {
                        dismiss()
                    }
                    .frame(maxWidth: 460)
                }
            }
            .padding(Theme.Spacing.xl)
        }
    }

    @ViewBuilder
    private var inAppBody: some View {
        // AVPlayer can only open MP4/M4V/MOV/HLS. For anything else (MKV, AVI,
        // WebM, or unknown), use the VLC-backed player which handles all formats.
        // The user's preferred built-in player can force one engine, and a recovery
        // override (from "Try other player") forces a specific engine for retry.
        if useVLCEngine {
            VLCPlayerView(item: item, series: series)
        } else {
            avPlayerBody
        }
    }

    /// Whether to use the VLC engine, honoring any recovery override first, then the
    /// normal routing. AVPlayer is never forced for a format it can't open.
    private var useVLCEngine: Bool {
        if let override = engineOverride {
            switch override {
            case .vlc:      return true
            case .avPlayer: return PlaybackEngineRouter.isAVPlayerCompatible(for: item) ? false : true
            }
        }
        return PlaybackEngineRouter.shouldUseVLC(for: item, preference: settings.builtInPlayer)
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
                AVPlayerContainer(player: model.player,
                                  onExitFullscreen: { dismiss() },
                                  nextEpisodeTitle: preparedNext?.title,
                                  onPlayNext: preparedNext != nil ? { playNext() } : nil)
                    .ignoresSafeArea()
            case .failed(let message):
                playbackRecovery(message: message)
            }
        }
        .onAppear {
            model.configure(progressStore: progress,
                            settings: settings,
                            trakt: env.trakt,
                            openSubtitles: env.openSubtitles)
            // If there's saved progress, ask Resume or Restart before starting.
            if let pos = progress.resumePosition(for: item.id), pos > 30, !didChooseResume {
                resumePromptPosition = pos
            } else {
                model.start()
                prepareNextEpisode()
            }
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
                preferences: settings.streamPreferences,
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
    /// tvOS only: when a next episode is queued, its title and a play action are
    /// provided so a focusable "Next Episode" button can be shown in the native
    /// transport bar (contextual actions). nil hides the button.
    var nextEpisodeTitle: String? = nil
    var onPlayNext: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(onExitFullscreen: onExitFullscreen) }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.delegate = context.coordinator
        // Native transport UI (scrub bar, subtitle/audio menu, fullscreen button).
        vc.showsPlaybackControls = true
        vc.allowsPictureInPicturePlayback = true
        #if os(iOS)
        // Inline PiP only exists on iOS; tvOS has no inline video surface.
        vc.canStartPictureInPictureAutomaticallyFromInline = true
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
        #if os(tvOS)
        // Keep the "Next Episode" contextual action in sync. It renders as a focusable
        // button in the native transport bar, reachable with the remote.
        context.coordinator.onPlayNext = onPlayNext
        if let title = nextEpisodeTitle, onPlayNext != nil {
            let action = UIAction(title: "Next: \(title)",
                                  image: UIImage(systemName: "forward.end.fill")) { [weak coordinator = context.coordinator] _ in
                coordinator?.onPlayNext?()
            }
            uiViewController.contextualActions = [action]
        } else {
            uiViewController.contextualActions = []
        }
        #endif
    }

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        let onExitFullscreen: (() -> Void)?
        var onPlayNext: (() -> Void)?
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
