//
//  VLCPlayerView.swift
//  Nova
//
//  The player screen used for formats AVPlayer can't open. Hosts the VLC video
//  surface and an Apple TV-style overlay: title metadata, play/pause, ten-second
//  skips, timeline, subtitles/audio, aspect controls, and exit actions. Resume and
//  progress saving are handled by VLCPlayerModel.
//

import SwiftUI
#if canImport(VLCKitSPM)
import VLCKitSPM
#endif
#if os(iOS)
import UniformTypeIdentifiers
#endif

struct VLCPlayerView: View {
    let item: MediaItem
    var series: CatalogItem?
    /// Called when the stream link itself is dead so the picker can fail over.
    var onStreamExpired: (() -> Void)?
    /// When true (from the minimized Now Playing bar), skip the Resume/Start Over
    /// prompt and continue the same stream at the saved position with no prompt.
    var autoResume: Bool = false
    /// Asks the host to reopen this title in the Apple player. `automatic` is true
    /// for the one-time fallback after a VLC failure on an Apple-compatible file.
    var onTryOtherEngine: ((_ automatic: Bool) -> Bool)? = nil

    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var progress: PlaybackProgressStore
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicAccent) private var accent
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var model: VLCPlayerModel
    @State private var controlsVisible = false
    #if os(tvOS)
    @FocusState private var surfaceFocused: Bool
    @FocusState private var playPauseFocused: Bool
    #endif
    @State private var showDiagnostics = false
    #if os(iOS)
    /// Non-nil while a horizontal drag-to-seek is in progress; holds the time the
    /// scrub started from so the HUD can show a signed delta.
    @State private var scrubbingFrom: TimeInterval? = nil
    @State private var scrubTarget: TimeInterval = 0
    #endif
    @State private var resumePromptPosition: TimeInterval?
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var hasStarted = false
    @State private var showSubtitleImporter = false
    @State private var preparedNext: MediaItem?
    @State private var navigateNext: MediaItem?
    @State private var upNextDismissed = false
    @State private var showBufferingBadge = false
    @State private var skipFeedback: SkipFeedback?
    @State private var skipFeedbackTask: Task<Void, Never>?
    @State private var showSleepTimer = false
    #if os(iOS)
    @State private var showChapters = false
    #endif

    /// Transient "−10 / +10" bubble shown after a skip.
    struct SkipFeedback: Equatable {
        let id = UUID()
        let forward: Bool
        let seconds: Int
    }


    private var hasNextEpisode: Bool { preparedNext != nil }

    #if os(iOS)
    private var subtitleTypes: [UTType] {
        // .srt/.ass/.vtt aren't all system-declared; fall back to plain text + data.
        [UTType("public.subrip") ?? .plainText, .plainText, .text, .data]
    }
    #endif

    init(item: MediaItem, series: CatalogItem? = nil,
         onStreamExpired: (() -> Void)? = nil, autoResume: Bool = false,
         onTryOtherEngine: ((_ automatic: Bool) -> Bool)? = nil) {
        self.item = item
        self.series = series
        self.onStreamExpired = onStreamExpired
        self.autoResume = autoResume
        self.onTryOtherEngine = onTryOtherEngine
        _model = StateObject(wrappedValue: VLCPlayerModel(item: item))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch model.state {
            case .loading:
                PlayerArtworkBackdrop(item: item)
                LoadingView(message: "Preparing \(item.displayTitle)…", systemImage: "play.fill")
            case .ready:
                videoSurface
                #if os(iOS)
                // UIKit gesture surface, BENEATH the controls so button taps land
                // first. Tap toggles controls; a horizontal drag scrubs the timeline
                // (direction-locked, so vertical drags are ignored).
                PlayerGestureOverlay(
                    onTap: {
                        if controlsVisible { hideControls() } else { revealControls() }
                    },
                    onScrub: { state, fraction in
                        handleScrub(state: state, fraction: fraction)
                    },
                    onDoubleTap: { fraction in
                        // Left third skips back, right third forward, middle toggles.
                        if fraction < 0.38 { skip(forward: false) }
                        else if fraction > 0.62 { skip(forward: true) }
                        else { Haptics.impact(.light); model.togglePlayPause() }
                    },
                    onSwipeDown: {
                        model.minimizeAndSave()
                        dismiss()
                    }
                )
                .ignoresSafeArea()

                // Live scrub HUD: shows the target time while dragging.
                if let from = scrubbingFrom {
                    let delta = scrubTarget - from
                    VStack(spacing: 4) {
                        Text(timeString(scrubTarget))
                            .font(.appFont(34, weight: .bold))
                            .foregroundStyle(.white)
                        Text(String(format: "%@%@", delta >= 0 ? "+" : "-", timeString(abs(delta))))
                            .font(.appFont(17, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.md)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .transition(.opacity)
                    .allowsHitTesting(false)
                }
                #endif
                if showBufferingBadge {
                    BufferingBadge()
                        .transition(.opacity)
                }

                if let skipFeedback {
                    SkipFeedbackBubble(feedback: skipFeedback)
                        .frame(maxWidth: .infinity, alignment: skipFeedback.forward ? .trailing : .leading)
                        .padding(.horizontal, Theme.scaled(80, min: 36))
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                        .allowsHitTesting(false)
                }

                #if os(tvOS)
                if controlsVisible {
                    activeOverlay
                        .transition(.opacity)
                        .onExitCommand { hideControls() }
                        .onPlayPauseCommand { model.togglePlayPause(); scheduleHideControls() }
                }
                #else
                activeOverlay
                    .opacity(controlsVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.25), value: controlsVisible)
                #endif

                // Above the controls so its buttons stay tappable while they show.
                upNextCard

                // Diagnostics panel (toggled from the controls).
                if showDiagnostics {
                    VStack {
                        HStack {
                            Spacer()
                            PlaybackDiagnostics(
                                item: model.item,
                                engine: .vlc,
                                currentTime: model.currentTime,
                                duration: model.duration,
                                isBuffering: model.isBuffering,
                                onClose: { showDiagnostics = false }
                            )
                            .padding(Theme.Spacing.lg)
                        }
                        Spacer()
                    }
                    .transition(.opacity)
                }

                #if os(tvOS)
                // Apple TV player behavior: while the panel is hidden an invisible
                // focused surface owns the remote. Left/right swipes skip 10s; select
                // or an up/down swipe opens the panel (focus lands on play/pause); the
                // play/pause button always toggles playback; Menu exits and saves.
                if !controlsVisible {
                    Color.clear
                        .contentShape(Rectangle())
                        .focusable(true)
                        .focused($surfaceFocused)
                        .onMoveCommand { direction in
                            switch direction {
                            case .left:  skip(forward: false)
                            case .right: skip(forward: true)
                            case .up, .down: revealControls()
                            @unknown default: revealControls()
                            }
                        }
                        .onTapGesture { revealControls() }
                        .accessibilityAddTraits(.isButton)
                        .onPlayPauseCommand { model.togglePlayPause() }
                        .onAppear { surfaceFocused = true }
                        .onExitCommand { model.minimizeAndSave(); dismiss() }
                }
                #endif
            case .failed(let message):
                failureRecovery(message: message)
                    .task(id: message) {
                        // One automatic hand-off to the Apple player when VLC fails on a
                        // file AVPlayer can open. The host allows this once per title.
                        guard canTryAppleEngine,
                              PlaybackFailureReason.classify(message).suggestsOtherEngine else { return }
                        await Task.yield()
                        if onTryOtherEngine?(true) == true { model.stopAndSave() }
                    }
            }
        }
        .onAppear {
            model.configure(progressStore: progress,
                            settings: settings,
                            trackers: env.trackers,
                            catalog: env.catalog,
                            openSubtitles: env.openSubtitles,
                            libraryStore: env.library)
            // Guard against SwiftUI re-running onAppear (e.g. after a sheet dismiss or
            // a parent nav change), which would otherwise restart the video.
            if !hasStarted {
                hasStarted = true
                // If there's saved progress, ask Resume or Start Over before starting;
                // otherwise begin immediately.
                if !autoResume, let pos = model.savedResumePosition {
                    resumePromptPosition = pos
                } else {
                    model.start()
                }
            }
            scheduleHideControls()
            Task { await prepareNextEpisode() }
        }
        .onDisappear {
            model.minimizeAndSave()
            hideControlsTask?.cancel()
            skipFeedbackTask?.cancel()
        }
        .onChange(of: model.isBuffering) { _, buffering in
            // Short rebuffers resolve before the badge appears, so it never flickers.
            guard buffering else {
                withAnimation(.easeOut(duration: 0.2)) { showBufferingBadge = false }
                return
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard model.isBuffering else { return }
                withAnimation(.easeIn(duration: 0.2)) { showBufferingBadge = true }
            }
        }
        .onChange(of: model.isPlaying) { _, playing in
            // Paused playback keeps its controls; hiding resumes once playing again.
            if playing {
                if controlsVisible { scheduleHideControls() }
            } else if model.state == .ready, !controlsVisible, resumePromptPosition == nil {
                revealControls()
            }
        }
        .onChange(of: model.didFinish) { _, finished in
            if finished { handleFinish() }
        }
        .sheet(isPresented: $showSleepTimer) {
            // Pauses whichever player is active when the timer fires, even if
            // playback has moved on to the next episode by then.
            NovaSleepTimerSheet(onPause: { PlaybackCoordinator.shared.pauseActive() })
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.checkpointProgress() }
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
        #if os(iOS)
        .statusBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        // True fullscreen: also dim the home indicator and keep the screen awake
        // for the duration of playback.
        .persistentSystemOverlays(.hidden)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .sheet(isPresented: $showChapters) {
            NovaChapterListSheet(chapters: NovaChapterParser.chapters(from: model.item),
                                 currentPosition: model.currentTime) { chapter in
                model.seek(to: chapter.startSeconds)
            }
        }
        #endif
        .sheet(isPresented: $model.showSubtitlePicker) {
            trackPicker
            #if os(iOS)
            // Half-height by default with a grab handle, like system pickers.
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            #endif
        }
        .navigationDestination(item: $navigateNext) { next in
            VLCPlayerView(item: next, series: series)
        }
    }

    // MARK: - Next episode

    private func prepareNextEpisode() async {
        guard let series, let ep = item.episode else { return }
        let ref = EpisodeRef(season: ep.season, number: ep.number)
        guard let nextInfo = env.catalog.nextEpisode(after: ref, in: series) else { return }
        // Resolve the best stream for the next episode in the background.
        let nextRef = EpisodeRef(season: nextInfo.season, number: nextInfo.number)
        let streams = await env.catalog.streams(for: series.contentID,
                                                 episode: nextRef,
                                                 preferredQuality: settings.preferredStreamQuality)
        // Same automatic choice as the Apple player: honors stream filters, quality
        // preferences and "cached sources only" instead of taking the first result.
        guard !Task.isCancelled,
              let best = StreamRanker.autoSelect(streams,
                                                 preferences: settings.streamPreferences,
                                                 requireCached: settings.requireCachedStreams) else { return }
        if let playable = try? await env.catalog.makePlayable(stream: best, catalog: series, episode: nextInfo) {
            await MainActor.run { preparedNext = playable }
        }
    }

    private func playNextEpisode() {
        guard let next = preparedNext else { return }
        env.library.add(next)
        model.stopAndSave()
        navigateNext = next
    }

    /// End of playback: continue to the prepared next episode when Auto-Play is on
    /// and the viewer didn't hide Up Next; otherwise close the player.
    private func handleFinish() {
        if hasNextEpisode, settings.autoPlayNext, !upNextDismissed {
            playNextEpisode()
        } else {
            model.stopAndSave()
            dismiss()
        }
    }

    // MARK: - Up Next

    /// Shown for the final 30 seconds of an episode with a prepared successor.
    private var showsUpNext: Bool {
        hasNextEpisode && !upNextDismissed && model.duration > 120
            && model.remainingTime > 0 && model.remainingTime <= 30
    }

    @ViewBuilder
    private var upNextCard: some View {
        if showsUpNext, let next = preparedNext {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    UpNextCard(next: next,
                               secondsRemaining: Int(model.remainingTime.rounded(.up)),
                               autoPlays: settings.autoPlayNext,
                               onPlay: { Haptics.impact(.medium); playNextEpisode() },
                               onHide: { withAnimation { upNextDismissed = true } })
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.bottom, controlsVisible ? Theme.scaled(220, min: 170) : Theme.Spacing.xl)
            .transition(.move(edge: .trailing).combined(with: .opacity))
            .animation(Theme.Motion.spring, value: controlsVisible)
        }
    }

    // MARK: - Skips and recovery

    private func skip(forward: Bool, seconds: Int = 10) {
        Haptics.impact(.light)
        if forward { model.skipForward(seconds) } else { model.skipBackward(seconds) }
        let running = (skipFeedback?.forward == forward) ? (skipFeedback?.seconds ?? 0) : 0
        withAnimation(.easeOut(duration: 0.15)) {
            skipFeedback = SkipFeedback(forward: forward, seconds: running + seconds)
        }
        skipFeedbackTask?.cancel()
        skipFeedbackTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.2)) { skipFeedback = nil }
        }
        if controlsVisible { scheduleHideControls() }
    }

    /// VLC can hand a failed file to the Apple player when AVPlayer supports it.
    private var canTryAppleEngine: Bool {
        onTryOtherEngine != nil && PlaybackEngineRouter.isAVPlayerCompatible(for: item)
    }

    private func failureRecovery(message: String) -> some View {
        let reason = PlaybackFailureReason.classify(message)
        return ZStack {
            PlayerArtworkBackdrop(item: item)
            VStack(spacing: Theme.Spacing.lg) {
                Image(systemName: reason.systemImage)
                    .font(.appFont(52, weight: .semibold))
                    .foregroundStyle(Theme.Colors.error)
                    .accessibilityHidden(true)
                Text("Playback failed")
                    .font(.appFont(28, weight: .bold))
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                Text(reason.message)
                    .font(.appFont(19))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 560)

                VStack(spacing: Theme.Spacing.sm) {
                    if canTryAppleEngine {
                        FocusableButton(title: "Try Apple Player", systemImage: "arrow.triangle.2.circlepath",
                                        prominent: reason.suggestsOtherEngine) {
                            if onTryOtherEngine?(false) == true { model.stopAndSave() }
                        }
                        .frame(maxWidth: 440)
                    }
                    FocusableButton(title: "Retry", systemImage: "gobackward",
                                    prominent: !canTryAppleEngine && onStreamExpired == nil) {
                        model.restart()
                    }
                    .frame(maxWidth: 440)
                    if onStreamExpired != nil {
                        FocusableButton(title: "Try Next Stream", systemImage: "forward.fill",
                                        prominent: reason.suggestsDifferentStream) {
                            model.stopAndSave()
                            onStreamExpired?()
                            dismiss()
                        }
                        .frame(maxWidth: 440)
                    }
                    FocusableButton(title: "Go Back", systemImage: "chevron.left") {
                        model.stopAndSave()
                        dismiss()
                    }
                    .frame(maxWidth: 440)
                }
            }
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: 640)
            .cinematicGlass(radius: Theme.Radius.largeCard)
            .padding(Theme.Spacing.edge)
        }
    }

    // MARK: - Video surface

    private var videoSurface: some View {
        #if canImport(VLCKitSPM)
        // "Fill" zooms the surface slightly to crop letterboxing; "fit" shows it whole.
        // Done at the view layer so it never touches fragile VLCKit KVC keys.
        VLCVideoSurface(player: model.mediaPlayer)
            .scaleEffect(model.fillScreen ? 1.18 : 1.0)
            .ignoresSafeArea()
            .clipped()
            .animation(.easeInOut(duration: 0.2), value: model.fillScreen)
        #else
        Color.black.ignoresSafeArea()
        #endif
    }

    // MARK: - Overlay

    /// Nova uses one Apple-style playback overlay on every device. Legacy persisted
    /// choices still decode, but no longer fragment player behavior or focus order.
    @ViewBuilder
    private var activeOverlay: some View {
        nativeOverlay
    }

    // MARK: - Native-style overlay

    /// An Apple-player-style overlay: the top control cluster stays for parity, but
    /// the bottom is a left-aligned title over a thin full-width scrubber with
    /// elapsed and remaining time, plus a compact text button row (Info / Audio &
    /// Subtitles / Aspect / Diagnostics) echoing the native transport bar.
    private var nativeOverlay: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.70), location: 0),
                    .init(color: .clear, location: 0.28),
                    .init(color: .clear, location: 0.58),
                    .init(color: .black.opacity(0.92), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: Theme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.item.displayTitle)
                            .font(.appFont(30, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        HStack(spacing: Theme.Spacing.sm) {
                            if !playerMetadataLine.isEmpty {
                                Text(playerMetadataLine)
                                    .font(.appFont(17, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.72))
                                    .lineLimit(1)
                            }
                            if abs(model.playbackRate - 1) > 0.01 {
                                Text(NovaSpeedControl.label(for: model.playbackRate))
                                    .font(.appFont(13, weight: .bold))
                                    .monospacedDigit()
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(.white, in: Capsule())
                                    .accessibilityLabel("Playback speed \(NovaSpeedControl.label(for: model.playbackRate))")
                            }
                        }
                    }
                    Spacer(minLength: Theme.Spacing.md)
                    playerExitControls
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.lg)
                #if os(iOS)
                .safeAreaPadding(.top)
                #endif
                #if os(tvOS)
                .focusSection()
                #endif

                Spacer()

                VStack(spacing: Theme.Spacing.md) {
                    HStack(spacing: Theme.Spacing.lg) {
                        transportButton("gobackward.10", accessibility: "Back 10 seconds") {
                            skip(forward: false); revealControls()
                        }

                        Button {
                            // Light tap on play/pause (no-op on tvOS).
                            Haptics.impact(.light)
                            model.togglePlayPause(); revealControls()
                        } label: {
                            Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                                .font(.appFont(32, weight: .semibold))
                                .foregroundStyle(.black)
                                .frame(width: Theme.scaled(78, min: 64),
                                       height: Theme.scaled(78, min: 64))
                                .background(.white, in: Circle())
                                .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
                        #if os(tvOS)
                        .focused($playPauseFocused)
                        #endif

                        transportButton("goforward.10", accessibility: "Forward 10 seconds") {
                            skip(forward: true); revealControls()
                        }
                    }

                    VStack(spacing: 6) {
                        #if os(iOS)
                        TapSeekBar(value: model.currentTime,
                                   duration: max(model.duration, 1),
                                   onScrubbing: { scrubbing in
                                       if scrubbing { hideControlsTask?.cancel() } else { scheduleHideControls() }
                                   }) { target in
                            model.seek(to: target)
                            revealControls()
                        }
                        #else
                        TimelineBar(progress: model.duration > 0 ? model.currentTime / model.duration : 0)
                        #endif

                        HStack {
                            Text(timeString(model.currentTime))
                            Spacer()
                            if let endsAt = endsAtLabel {
                                Text(endsAt)
                                    .foregroundStyle(.white.opacity(0.6))
                                Spacer()
                            }
                            Text("-\(timeString(max(model.duration - model.currentTime, 0)))")
                        }
                        .font(.appFont(14, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.78))
                    }

                    HStack(spacing: Theme.Spacing.sm) {
                        Button {
                            model.showSubtitlePicker = true
                        } label: {
                            Label("Audio & Subtitles", systemImage: "captions.bubble.fill")
                                .labelStyle(.iconOnly)
                                .font(.appFont(17, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.88))
                                .frame(width: 44, height: 44)
                                .background(.thinMaterial, in: Circle())
                                .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Audio and subtitles")
                        playerOptionsMenu
                    }
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.xl)
                #if os(iOS)
                .safeAreaPadding(.bottom)
                #endif
                #if os(tvOS)
                .focusSection()
                #endif
            }
        }
    }

    private func transportButton(_ symbol: String, accessibility: String,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.appFont(29, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Theme.scaled(58, min: 48),
                       height: Theme.scaled(58, min: 48))
                .background(.thinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
    }

    /// Minimal Apple-style exit controls kept separate from playback transport.
    private var playerExitControls: some View {
        HStack(spacing: Theme.Spacing.sm) {
            SleepTimerBadge { showSleepTimer = true }

            // Minimize: leave the player but keep the session so the floating bar can
            // resume it. Does NOT end playback — that's what the Stop button is for.
            Button { model.minimizeAndSave(); dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.appFont(22, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(Theme.Spacing.md)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Minimize")

        }
    }

    /// Keeps the playback surface calm: only transport is persistent. Less common
    /// actions remain one tap away and use the same menu on iPhone, iPad and tvOS.
    private var playerOptionsMenu: some View {
        Menu {
            if hasNextEpisode {
                Button { playNextEpisode() } label: {
                    Label("Play Next Episode", systemImage: "forward.end.fill")
                }
            }
            Button { model.showSubtitlePicker = true } label: {
                Label(model.isLoadingExternalSubtitles ? "Searching…" : "Audio & Subtitles",
                      systemImage: "captions.bubble.fill")
            }
            Menu {
                ForEach(NovaPlaybackSpeed.allCases) { speed in
                    Button {
                        model.setRate(speed.rawValue)
                        revealControls()
                    } label: {
                        if abs(model.playbackRate - speed.rawValue) < 0.01 {
                            Label(speed.label, systemImage: "checkmark")
                        } else {
                            Text(speed.label)
                        }
                    }
                }
            } label: {
                Label("Playback Speed (\(NovaSpeedControl.label(for: model.playbackRate)))", systemImage: "gauge.with.dots.needle.67percent")
            }
            #if os(iOS)
            if !NovaChapterParser.chapters(from: model.item).isEmpty {
                Button { showChapters = true } label: {
                    Label("Chapters", systemImage: "list.bullet.rectangle")
                }
            }
            #endif
            Button { showSleepTimer = true } label: {
                Label("Sleep Timer", systemImage: "timer")
            }
            Button { model.restartFromBeginning(); revealControls() } label: {
                Label("Start from Beginning", systemImage: "backward.end.fill")
            }
            Button { model.fillScreen.toggle(); revealControls() } label: {
                Label(model.fillScreen ? "Fit to Screen" : "Fill Screen",
                      systemImage: model.fillScreen
                        ? "arrow.down.right.and.arrow.up.left"
                        : "arrow.up.left.and.arrow.down.right")
            }
            Button { showDiagnostics.toggle(); revealControls() } label: {
                Label("Playback Diagnostics", systemImage: "waveform.path.ecg")
            }
            Divider()
            Button(role: .destructive) { model.stopAndSave(); dismiss() } label: {
                Label("Stop Playback", systemImage: "stop.fill")
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
                .font(.appFont(15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(.thinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Playback options")
    }

    /// A native-style text button: an SF Symbol above a small caption, no filled
    /// pill — reads like the native transport's text actions.
    private func nativeTextButton(_ title: String, systemImage: String,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.appFont(24, weight: .semibold))
                Text(title)
                    .font(.appFont(14, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(minWidth: Theme.scaled(64, min: 44))
            .contentShape(Rectangle())
        }
        .buttonStyle(NovaChipButtonStyle())
    }

    // MARK: - Resume prompt

    /// Asks whether to resume from the saved position or start over, mirroring the
    /// Apple player's prompt. Shown before VLC playback begins when progress exists.
    private func resumeRestartPrompt(position: TimeInterval) -> some View {
        ZStack {
            PlayerArtworkBackdrop(item: item)
            VStack(spacing: Theme.Spacing.lg) {
                Image(systemName: "play.circle")
                    .font(.appFont(56, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
                Text(model.item.title)
                    .font(.appFont(28, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("You left off at \(timeString(position)).")
                    .font(.appFont(20))
                    .foregroundStyle(Theme.Colors.textSecondary)
                ResumeProgressSummary(position: position, duration: item.duration)

                VStack(spacing: Theme.Spacing.sm) {
                    FocusableButton(title: "Resume from \(timeString(position))",
                                    systemImage: "play.fill", prominent: true) {
                        model.forceRestart = false
                        resumePromptPosition = nil
                        model.start()
                    }
                    .frame(maxWidth: 420)

                    FocusableButton(title: "Start from beginning",
                                    systemImage: "backward.end.fill") {
                        progress.reset(for: item)
                        model.forceRestart = true
                        resumePromptPosition = nil
                        model.start()
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
            .frame(maxWidth: 620)
            .cinematicGlass(radius: Theme.Radius.largeCard)
            .padding(Theme.Spacing.edge)
        }
    }

    // MARK: - Track picker

    private var trackPicker: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Subtitles", value: currentSubtitleSummary)
                    if let audio = model.audioTracks.first(where: { $0.id == model.selectedAudioTrackID }) {
                        LabeledContent("Audio", value: audio.name)
                    }
                } header: {
                    Text("Now Playing")
                }

                Section("Subtitles") {
                    Button {
                        Task { await model.refreshExternalSubtitles() }
                    } label: {
                        Label(model.isLoadingExternalSubtitles ? "Searching Subtitle Add-ons…" : "Download from Add-ons",
                              systemImage: "arrow.down.circle")
                            .padding(Theme.Spacing.sm)
                    }
                    .buttonStyle(NovaListRowStyle())
                    .listRowBackground(Color.clear)
                    .disabled(model.isLoadingExternalSubtitles || model.isDownloadingSubtitle)

                    trackChoice("Off", detail: "Disable subtitles", selected: model.subtitlesAreOff) {
                        model.disableSubtitles()
                    }

                    ForEach(model.externalSubtitleTracks) { track in
                        trackChoice(track.languageDisplay, detail: track.source,
                                    selected: model.selectedExternalSubtitleID == track.id,
                                    pending: model.pendingExternalSubtitleID == track.id) {
                            model.selectExternalSubtitle(track)
                        }
                    }

                    if !model.playerSubtitleTracks.isEmpty {
                        Text("Player tracks").font(.caption).foregroundStyle(.secondary).accessibilityAddTraits(.isHeader)
                    }
                    ForEach(model.playerSubtitleTracks) { track in
                        trackChoice(track.name, selected: model.selectedSubtitleTrackID == track.id) {
                            model.selectSubtitleTrack(track)
                        }
                    }

                    if model.isDownloadingSubtitle {
                        Button("Cancel subtitle download") { model.cancelPendingSubtitleSelection() }
                            .buttonStyle(NovaListRowStyle()).listRowBackground(Color.clear)
                    }
                    if let message = model.subtitleStatusMessage {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    #if os(iOS)
                    Button { showSubtitleImporter = true } label: {
                        Label("Add subtitle file…", systemImage: "plus.circle").padding(Theme.Spacing.sm)
                    }
                    .buttonStyle(NovaListRowStyle()).listRowBackground(Color.clear)
                    #endif
                }

                Section("Subtitle Size") {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text(model.subtitleScale.formatted(.percent.precision(.fractionLength(0))))
                            .monospacedDigit().accessibilityLabel("Subtitle size")
                        #if os(iOS)
                        Slider(value: $model.subtitleScale, in: SubtitleScalePolicy.range, step: 0.1)
                            .accessibilityLabel("Subtitle size")
                            .accessibilityValue(model.subtitleScale.formatted(.percent.precision(.fractionLength(0))))
                        #else
                        HStack(spacing: Theme.Spacing.md) {
                            Button { model.subtitleScale -= 0.1 } label: {
                                Label("Smaller", systemImage: "textformat.size.smaller").padding(Theme.Spacing.sm)
                            }
                            .buttonStyle(NovaChipButtonStyle(providesSurface: true))
                            .disabled(model.subtitleScale <= SubtitleScalePolicy.range.lowerBound)
                            Button { model.subtitleScale += 0.1 } label: {
                                Label("Larger", systemImage: "textformat.size.larger").padding(Theme.Spacing.sm)
                            }
                            .buttonStyle(NovaChipButtonStyle(providesSurface: true))
                            .disabled(model.subtitleScale >= SubtitleScalePolicy.range.upperBound)
                        }
                        #endif
                        Text("Subtitle preview").font(.system(size: 17 * model.subtitleScale))
                            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section {
                    HStack(spacing: Theme.Spacing.md) {
                        Button { model.subtitleDelay -= 0.25 } label: {
                            Label("Earlier", systemImage: "minus").padding(Theme.Spacing.sm)
                        }
                        .buttonStyle(NovaChipButtonStyle(providesSurface: true))
                        .accessibilityLabel("Show subtitles earlier")
                        Text(subtitleDelayLabel)
                            .monospacedDigit()
                            .frame(minWidth: 80)
                            .accessibilityLabel("Subtitle offset \(subtitleDelayLabel)")
                        Button { model.subtitleDelay += 0.25 } label: {
                            Label("Later", systemImage: "plus").padding(Theme.Spacing.sm)
                        }
                        .buttonStyle(NovaChipButtonStyle(providesSurface: true))
                        .accessibilityLabel("Show subtitles later")
                        if model.subtitleDelay != 0 {
                            Button("Reset") { model.subtitleDelay = 0 }
                                .buttonStyle(NovaChipButtonStyle(providesSurface: true))
                        }
                    }
                } header: {
                    Text("Subtitle Timing")
                } footer: {
                    Text("Adjust when subtitles appear. Nova remembers the offset for this title.")
                }

                if !model.audioTracks.isEmpty {
                    Section("Audio") {
                        ForEach(model.audioTracks) { track in
                            trackChoice(track.name, selected: model.selectedAudioTrackID == track.id) {
                                model.selectAudioTrack(track)
                            }
                        }
                    }
                }
            }
            #if os(iOS)
            .scrollContentBackground(.hidden)
            #endif
            .background(Theme.Colors.appBackground)
            .navigationTitle("Audio & Subtitles")
            .onAppear { model.refreshTracks() }
            .onDisappear { model.cancelPendingSubtitleSelection() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { model.cancelPendingSubtitleSelection(); model.showSubtitlePicker = false }
                }
            }
            #if os(iOS)
            .fileImporter(isPresented: $showSubtitleImporter,
                          allowedContentTypes: subtitleTypes,
                          allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    let needsStop = url.startAccessingSecurityScopedResource()
                    model.addExternalSubtitle(url)
                    if needsStop { url.stopAccessingSecurityScopedResource() }
                }
            }
            #endif
        }
        .presentationBackground(Theme.Colors.appBackground)
    }

    private func trackChoice(_ title: String, detail: String? = nil, selected: Bool,
                             pending: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).foregroundStyle(.primary)
                    if let detail, !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if pending { ProgressView().tint(.primary) }
                if selected { Image(systemName: "checkmark").accessibilityHidden(true) }
            }.padding(Theme.Spacing.sm)
        }
        .buttonStyle(NovaListRowStyle(selected: selected))
        .listRowBackground(Color.clear)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue([detail, selected ? "Selected" : nil, pending ? "Downloading" : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var currentSubtitleSummary: String {
        if model.subtitlesAreOff { return "Off" }
        if let externalID = model.selectedExternalSubtitleID,
           let track = model.externalSubtitleTracks.first(where: { $0.id == externalID }) {
            return "\(track.languageDisplay) · \(track.source)"
        }
        if let id = model.selectedSubtitleTrackID,
           let track = model.subtitleTracks.first(where: { $0.id == id }) {
            return track.name
        }
        return "Off"
    }

    private var subtitleDelayLabel: String {
        let delay = model.subtitleDelay
        if abs(delay) < 0.001 { return "0.00 s" }
        return String(format: "%+.2f s", delay)
    }

    /// "Ends at 9:42 PM" — wall-clock finish time at the current playback speed.
    private var endsAtLabel: String? {
        guard model.duration > 0, item.sourceType != .liveTV else { return nil }
        let rate = max(model.playbackRate, 0.25)
        let remaining = max(model.duration - model.currentTime, 0) / rate
        guard remaining.isFinite else { return nil }
        let end = Date().addingTimeInterval(remaining)
        return "Ends at \(end.formatted(date: .omitted, time: .shortened))"
    }

    // MARK: - Drag-to-seek

    #if os(iOS)
    /// Maps a horizontal pan (reported as a signed fraction of the surface width)
    /// to a scrub target. A full-width swipe spans the whole timeline.
    private func handleScrub(state: UIGestureRecognizer.State, fraction: CGFloat) {
        guard model.duration > 0 else { return }
        // A full-width swipe covers at most ten minutes, so long films scrub with
        // usable precision; short videos still span their whole length.
        let span = min(model.duration, 600)
        switch state {
        case .began:
            Haptics.selection()
            scrubbingFrom = model.currentTime
            scrubTarget = model.currentTime
            revealControls()
        case .changed:
            let base = scrubbingFrom ?? model.currentTime
            scrubTarget = min(max(base + Double(fraction) * span, 0), model.duration)
        case .ended:
            if scrubbingFrom != nil {
                model.seek(to: scrubTarget)
            }
            scrubbingFrom = nil
            scheduleHideControls()
        case .cancelled, .failed:
            scrubbingFrom = nil
        default:
            break
        }
    }
    #endif

    // MARK: - Controls visibility

    private func revealControls() {
        withAnimation(.easeInOut(duration: 0.25)) { controlsVisible = true }
        scheduleHideControls()
        #if os(tvOS)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)
            playPauseFocused = true
        }
        #endif
    }

    private func hideControls() {
        hideControlsTask?.cancel()
        withAnimation { controlsVisible = false }
        #if os(tvOS)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)
            surfaceFocused = true
        }
        #endif
    }

    private func scheduleHideControls() {
        hideControlsTask?.cancel()
        // On tvOS the controls are focused elements; hiding them after a few seconds
        // would snatch focus away mid-navigation. Use a longer, gentler timeout there
        // (playback/skip still reveal-and-reset it) so the user can move around the
        // top bar and transport without the overlay vanishing under them.
        #if os(tvOS)
        let delay: UInt64 = 12_000_000_000
        #else
        let delay: UInt64 = 4_000_000_000
        #endif
        hideControlsTask = Task {
            try? await Task.sleep(nanoseconds: delay)
            if Task.isCancelled { return }
            await MainActor.run {
                // Paused playback keeps its controls on screen.
                guard model.isPlaying else { return }
                withAnimation { controlsVisible = false }
            }
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let total = Int(t)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }

    /// Episode identifiers are already part of `displayTitle`; remove the same
    /// leading token from the metadata line so portrait playback does not announce
    /// S01E01 twice.
    private var playerMetadataLine: String {
        let parts = model.item.subtitleLine.components(separatedBy: " · ")
        guard let episode = model.item.episode else { return model.item.subtitleLine }
        let token = String(format: "S%02dE%02d", episode.season, episode.number)
        return parts.filter { $0.caseInsensitiveCompare(token) != .orderedSame }
            .joined(separator: " · ")
    }


}

#if os(iOS)
/// A timeline that seeks on a tap or a drag. While dragging it previews the target
/// (thicker track, thumb and time bubble) and seeks once on release, instead of
/// asking VLC for dozens of seeks per drag, which stuttered network streams.
private struct TapSeekBar: View {
    let value: TimeInterval
    let duration: TimeInterval
    var onScrubbing: ((Bool) -> Void)? = nil
    let onSeek: (TimeInterval) -> Void
    @State private var dragValue: TimeInterval?

    var body: some View {
        GeometryReader { proxy in
            let shown = dragValue ?? value
            let progress = min(max(shown / max(duration, 1), 0), 1)
            let dragging = dragValue != nil
            let trackHeight: CGFloat = dragging ? 9 : 5
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.22)).frame(height: trackHeight)
                Capsule().fill(.white).frame(width: max(trackHeight, proxy.size.width * progress), height: trackHeight)
                if dragging {
                    Circle().fill(.white)
                        .frame(width: 20, height: 20)
                        .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
                        .offset(x: proxy.size.width * progress - 10)
                    Text(Self.label(shown))
                        .font(.appFont(15, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.white, in: Capsule())
                        .fixedSize()
                        .offset(x: min(max(proxy.size.width * progress - 34, 0), max(proxy.size.width - 68, 0)), y: -32)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.15), value: dragging)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { location in
                        if dragValue == nil { onScrubbing?(true) }
                        dragValue = target(at: location.location.x, width: proxy.size.width)
                    }
                    .onEnded { location in
                        let final = target(at: location.location.x, width: proxy.size.width)
                        dragValue = nil
                        onScrubbing?(false)
                        onSeek(final)
                    }
            )
        }
        .frame(height: 32)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(Self.label(value)) of \(Self.label(duration)), \(Int((value / max(duration, 1)) * 100)) percent")
        .accessibilityAdjustableAction { direction in
            let delta = duration * 0.05 * (direction == .increment ? 1 : -1)
            onSeek(min(max(value + delta, 0), duration))
        }
    }

    private func target(at x: CGFloat, width: CGFloat) -> TimeInterval {
        guard width > 0 else { return value }
        return duration * min(max(Double(x / width), 0), 1)
    }

    static func label(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let total = Int(t)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
#endif

/// Non-interactive progress line used where the timeline is not directly scrubbed
/// (Apple TV, where the remote's left/right skips instead).
private struct TimelineBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            let clamped = progress.isFinite ? min(max(progress, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.22))
                Capsule().fill(.white).frame(width: max(6, proxy.size.width * clamped))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

// MARK: - Shared player chrome

/// Blurred title artwork behind loading, resume and failure states, so the player
/// never flashes to a bare black screen while a stream opens.
struct PlayerArtworkBackdrop: View {
    let item: MediaItem

    var body: some View {
        ZStack {
            Color.black
            if let artwork = item.backdropURL ?? item.posterURL {
                CachedAsyncImage(url: artwork, maxPixel: 1600) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                        .blur(radius: 20).scaleEffect(1.08)
                } placeholder: { Color.black }
            }
            Color.black.opacity(0.68)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// "Buffering…" capsule shown only when a rebuffer lasts long enough to notice.
struct BufferingBadge: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ProgressView().tint(.white)
            Text("Buffering…")
                .font(.appFont(17, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Buffering")
        .allowsHitTesting(false)
    }
}

/// Watched-percentage and time-left line for the resume prompt.
struct ResumeProgressSummary: View {
    let position: TimeInterval
    let duration: TimeInterval?

    var body: some View {
        if let duration, duration.isFinite, duration > 0, position.isFinite {
            let fraction = min(max(position / duration, 0), 1)
            let minutesLeft = max(1, Int(((duration - position) / 60).rounded(.up)))
            VStack(spacing: 6) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.2))
                        Capsule().fill(.white).frame(width: max(4, proxy.size.width * fraction))
                    }
                }
                .frame(width: 240, height: 4)
                Text("\(Int((fraction * 100).rounded()))% watched · \(minutesLeft >= 60 ? "\(minutesLeft / 60)h \(minutesLeft % 60)m" : "\(minutesLeft) min") left")
                    .font(.appFont(15, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Timer button in the player's top bar, visible only while a sleep timer runs.
private struct SleepTimerBadge: View {
    @ObservedObject private var manager = NovaSleepTimerManager.shared
    let onOpen: () -> Void

    var body: some View {
        if manager.isActive {
            Button(action: onOpen) {
                Label(manager.displayString, systemImage: "timer")
                    .font(.appFont(15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sleep timer, \(manager.displayString) remaining")
        }
    }
}

/// "−10 / +10" bubble after a skip; repeated skips accumulate.
private struct SkipFeedbackBubble: View {
    let feedback: VLCPlayerView.SkipFeedback

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: feedback.forward ? "goforward" : "gobackward")
            Text("\(feedback.forward ? "+" : "−")\(feedback.seconds)s")
                .monospacedDigit()
        }
        .font(.appFont(20, weight: .bold))
        .foregroundStyle(.white)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(.ultraThinMaterial, in: Capsule())
        .id(feedback.id)
        .accessibilityHidden(true)
    }
}

/// Final-seconds card for the next episode: artwork, title and either a countdown
/// (Auto-Play on) or a prompt, with Play Now and Hide.
private struct UpNextCard: View {
    let next: MediaItem
    let secondsRemaining: Int
    let autoPlays: Bool
    let onPlay: () -> Void
    let onHide: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                if let artwork = next.backdropURL ?? next.posterURL {
                    CachedAsyncImage(url: artwork, maxPixel: 480) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: { Theme.Colors.card }
                } else {
                    Theme.Colors.card
                }
            }
            .frame(width: Theme.scaled(150, min: 112), height: Theme.scaled(84, min: 63))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(autoPlays ? "Up Next in \(max(secondsRemaining, 0))s" : "Up Next")
                    .font(.appFont(13, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
                Text(next.displayTitle)
                    .font(.appFont(17, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                #if os(iOS)
                HStack(spacing: Theme.Spacing.sm) {
                    Button(action: onPlay) {
                        Label("Play Now", systemImage: "play.fill")
                            .font(.appFont(14, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 12).frame(minHeight: 36)
                            .background(.white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Button(action: onHide) {
                        Text("Hide")
                            .font(.appFont(14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).frame(minHeight: 36)
                            .background(.white.opacity(0.18), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Stays on this episode when it ends")
                }
                #else
                Text("Open the menu for Play Next Episode")
                    .font(.appFont(13))
                    .foregroundStyle(.white.opacity(0.6))
                #endif
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: Theme.scaled(440, min: 320), alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}

#if canImport(VLCKitSPM)
#if os(iOS) || os(tvOS)
import UIKit

/// Hosts the VLC media player's video output in a UIView.
struct VLCVideoSurface: UIViewRepresentable {
    let player: VLCMediaPlayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        player.drawable = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if player.drawable == nil { player.drawable = uiView }
    }
}
#endif
#endif
