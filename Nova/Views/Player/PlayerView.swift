//
//  PlayerView.swift
//  Nova
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
    /// Called when playback fails because the stream link itself is dead (expired,
    /// timed out, or unresolvable). The picker uses this to mark the stream and
    /// automatically fail over to the next best one.
    var onStreamExpired: (() -> Void)?
    /// When true (used by the minimized Now Playing bar), skip the Resume/Restart
    /// prompt and continue the same stream at the saved position with no interruption.
    var autoResume: Bool = false

    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var progress: PlaybackProgressStore
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var model: PlayerModel
    @State private var preparedNext: MediaItem?      // pre-resolved, not yet navigated
    @State private var navigateNext: MediaItem?      // bound to navigationDestination
    @State private var prepareTask: Task<Void, Never>?

    // Resume-or-restart prompt state.
    @State private var resumePromptPosition: TimeInterval?
    @State private var didChooseResume = false

    // One-tap recovery: when set, forces a specific engine for this session,
    // overriding the automatic/preference routing (used by "Try other player").
    @State private var engineOverride: PlaybackEngine?
    @State private var didAutoFallbackSMB = false
    // #4 External-player return prompt: external apps don't report progress back, so on
    // return we ask the viewer how far they got and update progress/watched accordingly.
    @State private var didOpenExternal = false
    @State private var showExternalReturnPrompt = false

    init(item: MediaItem, series: CatalogItem? = nil,
         onStreamExpired: (() -> Void)? = nil, autoResume: Bool = false) {
        self.item = item
        self.series = series
        self.onStreamExpired = onStreamExpired
        self.autoResume = autoResume
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
            // Container so the prompt springs in with scale + fade instead of popping.
            ZStack {
                if let pos = resumePromptPosition {
                    resumeRestartPrompt(position: pos)
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                }
            }
            .animation(Theme.Motion.spring, value: resumePromptPosition == nil)
        }
        .overlay {
            // Night mode: a gentle dark veil over the video to ease late viewing.
            // Doesn't intercept taps/focus so playback controls still work.
            // Fades in/out when toggled rather than snapping.
            ZStack {
                if settings.nightMode {
                    Color.black.opacity(0.22)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: settings.nightMode)
            .allowsHitTesting(false)
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
                        // Light tap on resuming playback (no-op on tvOS).
                        Haptics.impact(.light)
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
                        progress.reset(for: item)
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
                    FocusableButton(title: onStreamExpired != nil && reason.suggestsDifferentStream
                                        ? "Try Next Stream" : "Choose a different stream",
                                    systemImage: "list.bullet",
                                    prominent: reason.suggestsDifferentStream) {
                        // If this was a dead-stream failure and the picker gave us a
                        // failover hook, tell it to skip this stream and auto-play the
                        // next before we pop back.
                        if reason.suggestsDifferentStream { onStreamExpired?() }
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
            VLCPlayerView(item: item, series: series, onStreamExpired: onStreamExpired, autoResume: autoResume)
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
                        message: "Install it, or turn off external playback in Settings to play in Nova.",
                        onBack: { dismiss() }
                    )
                } else if showExternalReturnPrompt {
                    externalReturnPrompt
                } else {
                    ProgressView().tint(.white)
                    Text("Opening in \(settings.preferredExternalPlayer.title)…")
                        .font(.appFont(20)).foregroundStyle(.white)
                }
            }
        }
        .onAppear {
            guard !didOpenExternal else { return }
            didOpenExternal = true
            let ok = settings.preferredExternalPlayer.open(item.playbackURL)
            if ok {
                // The external app doesn't report progress; keep this screen and ask on
                // return how far they got (Finished / Partial / Close).
                showExternalReturnPrompt = true
            } else {
                handoffFailed = true
            }
        }
    }

    /// Shown after handing off to an external player, since those apps don't report
    /// playback progress back to Nova.
    private var externalReturnPrompt: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text("How did playback go?")
                .font(.appFont(26, weight: .bold)).foregroundStyle(.white)
            Text("\(settings.preferredExternalPlayer.title) doesn't report progress back to Nova. Tell it how far you got so Continue Watching and sync stay accurate.")
                .font(.appFont(16)).foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Spacing.lg)
            FocusableButton(title: "Finished watching", systemImage: "checkmark.circle.fill", prominent: true) {
                markExternal(percent: 100)
            }.frame(maxWidth: 420)
            FocusableButton(title: "Partially watched (50%)", systemImage: "circle.lefthalf.filled") {
                markExternal(percent: 50)
            }.frame(maxWidth: 420)
            FocusableButton(title: "Just close", systemImage: "xmark") { dismiss() }
                .frame(maxWidth: 420)
        }
        .padding(28).frame(maxWidth: 480)
    }

    /// Record external playback outcome to local progress and any connected trackers.
    private func markExternal(percent: Double) {
        if let duration = item.duration, duration > 0 {
            progress.save(position: duration * (percent / 100), duration: duration, for: item)
        }
        if let cid = item.contentID {
            let ep = item.episode
            Task { await env.trackers.scrobble(action: .stop, contentID: cid, episode: ep, progress: percent) }
        }
        dismiss()
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
                                  title: item.displayTitle,
                                  subtitle: item.subtitleLine,
                                  onExitFullscreen: { model.checkpointProgress(); dismiss() },
                                  nextEpisodeTitle: preparedNext?.title,
                                  onPlayNext: preparedNext != nil ? { playNext() } : nil,
                                  onShowSubtitles: { model.showSubtitlePicker = true })
                    .ignoresSafeArea()

                if let subtitleText = model.activeSubtitleText, !subtitleText.isEmpty {
                    externalSubtitleOverlay(subtitleText)
                }

                #if os(iOS)
                avPlayerAccessoryBar
                #endif
            case .failed(let message):
                playbackRecovery(message: message)
                    .task(id: message) {
                        guard item.sourceType == .smb,
                              engineOverride == nil,
                              !didAutoFallbackSMB else { return }
                        didAutoFallbackSMB = true
                        await Task.yield()
                        engineOverride = .vlc
                    }
            }
        }
        .onAppear {
            model.configure(progressStore: progress,
                            settings: settings,
                            trackers: env.trackers,
                            openSubtitles: env.openSubtitles,
                            catalog: env.catalog)
            // If there's saved progress, ask Resume or Restart before starting —
            // unless this is a seamless resume from the minimized Now Playing bar, in
            // which case continue the same stream at the saved position with no prompt.
            if !autoResume, let pos = progress.resumePosition(for: item), !didChooseResume {
                resumePromptPosition = pos
            } else {
                model.start()
                prepareNextEpisode()
            }
        }
        .onDisappear { model.minimizeAndSave(); prepareTask?.cancel() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.checkpointProgress() }
        }
        .sheet(isPresented: $model.showSubtitlePicker) {
            SubtitlePickerView(
                tracks: model.availableSubtitles,
                selectedID: model.selectedSubtitleID,
                isLoading: model.isLoadingSubtitles,
                statusMessage: model.subtitleStatusMessage,
                onRefresh: { Task { await model.refreshSubtitlesFromProviders() } },
                onSelect: { model.selectSubtitle($0) }
            )
            #if os(iOS)
            // Half-height by default with a grab handle, like system pickers.
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            #endif
        }
        #if os(iOS)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(true)
        // True fullscreen: also dim the home indicator and keep the screen awake
        // for the duration of playback.
        .persistentSystemOverlays(.hidden)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        #endif
        .onChange(of: model.didFinish) { _, finished in
            if finished { handleFinish() }
        }
        .navigationDestination(item: $navigateNext) { next in
            PlayerView(item: next, series: series)
        }
    }

    private func externalSubtitleOverlay(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: Theme.scaled(28, min: 20), weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .shadow(color: .black, radius: 2, x: 0, y: 1)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Color.black.opacity(0.68),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .frame(maxWidth: Theme.contentMaxWidth(980))
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.bottom, Theme.scaled(118, min: 76))
        }
        .allowsHitTesting(false)
        .transition(.opacity)
        .animation(.easeOut(duration: 0.12), value: text)
    }

    #if os(iOS)
    /// Lightweight Apple-player accessory cluster. Transport remains native inside
    /// AVPlayerViewController; these actions expose Nova-specific subtitles and exit
    /// behavior without replacing Apple's play/pause and scrubber UI.
    private var avPlayerAccessoryBar: some View {
        VStack {
            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    model.minimizeAndSave()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.appFont(19, weight: .semibold))
                        .frame(width: 46, height: 46)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Minimize player")

                Spacer()

                Button {
                    model.showSubtitlePicker = true
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "captions.bubble.fill")
                            .font(.appFont(19, weight: .semibold))
                            .frame(width: 46, height: 46)
                            .background(.ultraThinMaterial, in: Circle())
                        if model.isLoadingSubtitles {
                            ProgressView()
                                .controlSize(.mini)
                                .offset(x: 2, y: -2)
                        }
                    }
                }
                .accessibilityLabel("Subtitles")

                Button {
                    model.stopAndSave()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.appFont(18, weight: .semibold))
                        .frame(width: 46, height: 46)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Stop playback")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Spacing.md)
            .safeAreaPadding(.top)
            Spacer()
        }
    }
    #endif

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
/// fullscreen toggle. PlayerView itself owns the full-screen presentation on iOS.
struct AVPlayerContainer: UIViewControllerRepresentable {
    let player: AVPlayer
    var title: String = ""
    var subtitle: String = ""
    /// Called when the user exits fullscreen so the presenting view can dismiss.
    var onExitFullscreen: (() -> Void)? = nil
    /// tvOS only: when a next episode is queued, its title and a play action are
    /// provided so a focusable "Next Episode" button can be shown in the native
    /// transport bar (contextual actions). nil hides the button.
    var nextEpisodeTitle: String? = nil
    var onPlayNext: (() -> Void)? = nil
    var onShowSubtitles: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onExitFullscreen: onExitFullscreen,
                    onPlayNext: onPlayNext,
                    onShowSubtitles: onShowSubtitles)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.title = title
        vc.delegate = context.coordinator
        // Native transport UI (scrub bar, subtitle/audio menu, fullscreen button).
        vc.showsPlaybackControls = true
        vc.allowsPictureInPicturePlayback = true
        #if os(iOS)
        // Inline PiP only exists on iOS; tvOS has no inline video surface.
        vc.canStartPictureInPictureAutomaticallyFromInline = true
        vc.videoGravity = .resizeAspect
        // PlayerView already presents this controller full-screen. Asking the
        // controller to present a second fullscreen layer hides Nova's subtitle and
        // exit accessories and causes awkward double-dismiss behavior.
        vc.entersFullScreenWhenPlaybackBegins = false
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
        uiViewController.title = title
        #if os(tvOS)
        // Keep the "Next Episode" contextual action in sync. It renders as a focusable
        // button in the native transport bar, reachable with the remote.
        context.coordinator.onPlayNext = onPlayNext
        context.coordinator.onShowSubtitles = onShowSubtitles
        var actions: [UIAction] = []
        if onShowSubtitles != nil {
            actions.append(UIAction(title: "Subtitles",
                                    image: UIImage(systemName: "captions.bubble.fill")) { [weak coordinator = context.coordinator] _ in
                coordinator?.onShowSubtitles?()
            })
        }
        if let nextTitle = nextEpisodeTitle, onPlayNext != nil {
            actions.append(UIAction(title: "Next: \(nextTitle)",
                                    image: UIImage(systemName: "forward.end.fill")) { [weak coordinator = context.coordinator] _ in
                coordinator?.onPlayNext?()
            })
        }
        uiViewController.contextualActions = actions
        #endif
    }

    // AVKit delivers these delegate callbacks on the main actor, matching the
    // coordinator's UI-bound state.
    @MainActor
    final class Coordinator: NSObject {
        let onExitFullscreen: (() -> Void)?
        var onPlayNext: (() -> Void)?
        var onShowSubtitles: (() -> Void)?
        init(onExitFullscreen: (() -> Void)?,
             onPlayNext: (() -> Void)?,
             onShowSubtitles: (() -> Void)?) {
            self.onExitFullscreen = onExitFullscreen
            self.onPlayNext = onPlayNext
            self.onShowSubtitles = onShowSubtitles
        }

        #if os(iOS)
        // Called when the user taps the exit-fullscreen (minimize) control. The method
        // is main-actor (see the class annotations above), so the transition
        // coordinator and our state are used directly. The Bool result is unused.
        func playerViewController(_ playerViewController: AVPlayerViewController,
                                  willEndFullScreenPresentationWithAnimationCoordinator
                                  coordinator: UIViewControllerTransitionCoordinator) {
            _ = coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                self?.onExitFullscreen?()
            }
        }
        #endif
    }
}

// The older iOS delegate declaration is not actor-annotated, so bridge that
// conformance explicitly. tvOS's declaration already matches the main actor and
// does not need (or accept) the compatibility annotation.
#if os(iOS)
extension AVPlayerContainer.Coordinator: @preconcurrency AVPlayerViewControllerDelegate {}
#else
extension AVPlayerContainer.Coordinator: AVPlayerViewControllerDelegate {}
#endif
