//
//  VLCPlayerView.swift
//  FrameTV
//
//  The player screen used for formats AVPlayer can't open. Hosts the VLC video
//  surface and a minimal overlay: play/pause, scrub, skip, subtitles/audio, and a
//  back button. Resume and progress saving are handled by VLCPlayerModel.
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

    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var progress: PlaybackProgressStore
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicAccent) private var accent

    @StateObject private var model: VLCPlayerModel
    @State private var controlsVisible = false
    @State private var showDiagnostics = false
    @State private var minimalControls = false
    @State private var resumePromptPosition: TimeInterval?
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var hasStarted = false
    @State private var showSubtitleImporter = false
    @State private var preparedNext: MediaItem?
    @State private var navigateNext: MediaItem?

    // Drag/swipe-to-seek state. `scrubTarget` is the previewed time while a drag is
    // in progress (nil when not scrubbing); committing applies it to the player.
    @State private var scrubTarget: TimeInterval?
    @State private var scrubStart: TimeInterval = 0

    private var hasNextEpisode: Bool { preparedNext != nil }

    #if os(iOS)
    private var subtitleTypes: [UTType] {
        // .srt/.ass/.vtt aren't all system-declared; fall back to plain text + data.
        [UTType("public.subrip") ?? .plainText, .plainText, .text, .data]
    }
    #endif

    init(item: MediaItem, series: CatalogItem? = nil) {
        self.item = item
        self.series = series
        _model = StateObject(wrappedValue: VLCPlayerModel(item: item))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch model.state {
            case .loading:
                LoadingView(message: "Preparing playback…")
            case .ready:
                videoSurface
                if model.isBuffering {
                    ProgressView().progressViewStyle(.circular).tint(.white)
                        .scaleEffect(1.4).padding(Theme.Spacing.lg)
                        .background(.ultraThinMaterial, in: Circle())
                }
                activeOverlay
                    .opacity(controlsVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.25), value: controlsVisible)

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

                // Seek preview shown while dragging/swiping to scrub.
                if let target = scrubTarget {
                    seekPreview(target: target)
                }
                #if os(iOS)
                // Horizontal drag anywhere on the video scrubs: drag right to go
                // forward, left to rewind. A vertical-ish drag is ignored so it
                // doesn't fight a tap. Tapping (no drag) reveals the controls.
                Color.clear.contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { value in handleScrubChange(translation: value.translation.width, width: nil) }
                            .onEnded { _ in commitScrub() }
                    )
                    .onTapGesture { revealControls() }
                #else
                // tvOS: left/right swipes on the remote touchpad skip; up/down or
                // select reveal the controls. Play/pause toggles playback. The catcher
                // only takes focus while controls are hidden - once they're visible,
                // focus moves to the overlay buttons (top bar and transport).
                Color.clear
                    .focusable(!controlsVisible)
                    .onMoveCommand { direction in
                        switch direction {
                        case .left:  model.skipBackward(10); revealControls()
                        case .right: model.skipForward(10); revealControls()
                        default:     revealControls()
                        }
                    }
                    .onPlayPauseCommand { model.togglePlayPause(); revealControls() }
                #endif
            case .failed(let message):
                ErrorStateView(
                    message: message,
                    onRetry: { model.restart() },
                    onBack: { model.stopAndSave(); dismiss() }
                )
            }
        }
        .onAppear {
            model.configure(progressStore: progress, settings: settings, trakt: env.trakt)
            // Guard against SwiftUI re-running onAppear (e.g. after a sheet dismiss or
            // a parent nav change), which would otherwise restart the video.
            if !hasStarted {
                hasStarted = true
                // If there's saved progress, ask Resume or Start Over before starting;
                // otherwise begin immediately.
                if let pos = model.savedResumePosition {
                    resumePromptPosition = pos
                } else {
                    model.start()
                }
            }
            scheduleHideControls()
            Task { await prepareNextEpisode() }
        }
        .onDisappear { model.stopAndSave(); hideControlsTask?.cancel() }
        .overlay {
            if let pos = resumePromptPosition {
                resumeRestartPrompt(position: pos)
            }
        }
        #if os(iOS)
        .statusBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        #endif
        .sheet(isPresented: $model.showSubtitlePicker) {
            trackPicker
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
                                                 episode: nextRef, preferredQuality: nil)
        guard let best = streams.first else { return }
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

    /// Chooses the overlay style from the user's setting. "Classic" is the original
    /// centered transport; "Native" mirrors Apple's player (left-aligned title, a
    /// thin scrubber with elapsed/remaining timestamps, and a text control row).
    @ViewBuilder
    private var activeOverlay: some View {
        switch settings.vlcOverlayStyle {
        case .classic: overlay
        case .native:  nativeOverlay
        }
    }

    // MARK: - Native-style overlay

    /// An Apple-player-style overlay: the top control cluster stays for parity, but
    /// the bottom is a left-aligned title over a thin full-width scrubber with
    /// elapsed and remaining time, plus a compact text button row (Info / Audio &
    /// Subtitles / Aspect / Diagnostics) echoing the native transport bar.
    private var nativeOverlay: some View {
        VStack {
            topBar
                .padding(Theme.Spacing.lg)
                #if os(tvOS)
                .focusSection()
                #endif

            Spacer()

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(model.item.title)
                    .font(.appFont(30, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.6), radius: 6, y: 2)

                // Thin scrubber with timestamps beneath, like the native bar.
                VStack(spacing: 4) {
                    #if os(iOS)
                    Slider(
                        value: Binding(
                            get: { model.currentTime },
                            set: { model.seek(to: $0) }
                        ),
                        in: 0...max(model.duration, 1)
                    )
                    .tint(accent)
                    #else
                    ProgressView(value: min(model.currentTime, model.duration),
                                 total: max(model.duration, 1))
                        .tint(accent)
                    #endif
                    HStack {
                        Text(timeString(model.currentTime))
                            .font(.appFont(14)).monospacedDigit()
                            .foregroundStyle(.white)
                        Spacer()
                        Text("-\(timeString(max(model.duration - model.currentTime, 0)))")
                            .font(.appFont(14)).monospacedDigit()
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }

                // Compact text control row (mirrors Info / Chapters / Settings).
                HStack(spacing: Theme.Spacing.xl) {
                    nativeTextButton("Play/Pause", systemImage: model.isPlaying ? "pause.fill" : "play.fill") {
                        model.togglePlayPause(); revealControls()
                    }
                    nativeTextButton("−15", systemImage: "gobackward.15") { model.skipBackward(); revealControls() }
                    nativeTextButton("+15", systemImage: "goforward.15") { model.skipForward(); revealControls() }
                    if hasNextEpisode {
                        nativeTextButton("Next", systemImage: "forward.end.fill") { playNextEpisode() }
                    }
                    nativeTextButton("Audio & Subtitles", systemImage: "captions.bubble") {
                        model.showSubtitlePicker = true
                    }
                    nativeTextButton(model.fillScreen ? "Fit" : "Fill",
                                     systemImage: model.fillScreen
                                        ? "arrow.down.right.and.arrow.up.left"
                                        : "arrow.up.left.and.arrow.down.right") {
                        model.fillScreen.toggle(); revealControls()
                    }
                    nativeTextButton("Diagnostics", systemImage: "waveform.path.ecg") {
                        showDiagnostics.toggle(); revealControls()
                    }
                }
                .padding(.top, Theme.Spacing.xs)
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xl)
            .padding(.top, Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.75)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .bottom)
            )
            #if os(tvOS)
            .focusSection()
            #endif
        }
    }

    /// The shared top control cluster (close, density, aspect, subtitles, diagnostics),
    /// reused by the native overlay so both styles expose the same top actions.
    private var topBar: some View {
        HStack {
            Button { model.stopAndSave(); dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.appFont(22, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(Theme.Spacing.md)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop")
            Spacer()
        }
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
        .buttonStyle(FrameChipButtonStyle())
    }

    // MARK: - Classic overlay

    private var overlay: some View {
        VStack {
            HStack {
                Button { model.stopAndSave(); dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.appFont(22, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(Theme.Spacing.md)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop")
                Spacer()
                // Overlay density toggle: minimal hides the secondary controls for a
                // cleaner view; full shows everything.
                Button { minimalControls.toggle(); revealControls() } label: {
                    Image(systemName: minimalControls ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                        .font(.appFont(22, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(Theme.Spacing.md)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(minimalControls ? "Show all controls" : "Minimal controls")

                if !minimalControls {
                    // Fill vs fit (the player already covers the screen; this toggles
                    // whether the video is cropped to fill or letterboxed to fit).
                    Button {
                        model.fillScreen.toggle(); revealControls()
                    } label: {
                        Image(systemName: model.fillScreen
                              ? "arrow.down.right.and.arrow.up.left"
                              : "arrow.up.left.and.arrow.down.right")
                            .font(.appFont(22, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(Theme.Spacing.md)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    Button { model.showSubtitlePicker = true } label: {
                        Image(systemName: "captions.bubble")
                            .font(.appFont(22, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(Theme.Spacing.md)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    // Diagnostics (engine, source, format, buffer health).
                    Button { showDiagnostics.toggle(); revealControls() } label: {
                        Image(systemName: "waveform.path.ecg")
                            .font(.appFont(22, weight: .semibold))
                            .foregroundStyle(showDiagnostics ? Theme.Colors.accent : .white)
                            .padding(Theme.Spacing.md)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Diagnostics")
                }
            }
            .padding(Theme.Spacing.lg)
            #if os(tvOS)
            .focusSection()
            #endif

            Spacer()

            // Transport controls.
            VStack(spacing: Theme.Spacing.sm) {
                // Scrubber.
                HStack(spacing: Theme.Spacing.sm) {
                    Text(timeString(model.currentTime))
                        .font(.appFont(15)).foregroundStyle(.white).monospacedDigit()
                    #if os(iOS)
                    Slider(
                        value: Binding(
                            get: { model.currentTime },
                            set: { model.seek(to: $0) }
                        ),
                        in: 0...max(model.duration, 1)
                    )
                    .tint(accent)
                    #else
                    // tvOS: a progress bar (scrubbing is done via the skip controls and
                    // the remote); Slider isn't available on tvOS.
                    ProgressView(value: min(model.currentTime, model.duration),
                                 total: max(model.duration, 1))
                        .tint(accent)
                    #endif
                    Text(timeString(model.duration))
                        .font(.appFont(15)).foregroundStyle(.white).monospacedDigit()
                }

                HStack(spacing: Theme.Spacing.xl) {
                    if !minimalControls {
                        controlButton("gobackward.15") { model.skipBackward() }
                    }
                    controlButton(model.isPlaying ? "pause.fill" : "play.fill", large: true) {
                        model.togglePlayPause(); revealControls()
                    }
                    if !minimalControls {
                        controlButton("goforward.15") { model.skipForward() }
                        if hasNextEpisode {
                            controlButton("forward.end.fill") { playNextEpisode() }
                        }
                    }
                }
            }
            .padding(Theme.Spacing.xl)
            .background(.ultraThinMaterial.opacity(0.4))
            #if os(tvOS)
            .focusSection()
            #endif
        }
    }

    private func controlButton(_ symbol: String, large: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.appFont(large ? 44 : 28, weight: .bold))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(controlAccessibilityLabel(for: symbol))
    }

    /// Human-readable VoiceOver labels for the transport SF Symbols.
    private func controlAccessibilityLabel(for symbol: String) -> String {
        switch symbol {
        case "gobackward.15":    return "Skip back 15 seconds"
        case "goforward.15":     return "Skip forward 15 seconds"
        case "pause.fill":       return "Pause"
        case "play.fill":        return "Play"
        case "forward.end.fill": return "Next episode"
        default:                 return "Playback control"
        }
    }

    // MARK: - Resume prompt

    /// Asks whether to resume from the saved position or start over, mirroring the
    /// Apple player's prompt. Shown before VLC playback begins when progress exists.
    private func resumeRestartPrompt(position: TimeInterval) -> some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
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
        }
    }

    // MARK: - Track picker

    private var trackPicker: some View {
        NavigationStack {
            List {
                Section("Subtitles") {
                    Button {
                        model.selectSubtitleTrack(nil)
                    } label: {
                        Label("Off", systemImage: "captions.bubble")
                    }
                    ForEach(model.subtitleTracks) { track in
                        Button(track.name) { model.selectSubtitleTrack(track) }
                    }
                    #if os(iOS)
                    Button {
                        showSubtitleImporter = true
                    } label: {
                        Label("Add subtitle file…", systemImage: "plus.circle")
                    }
                    #endif
                }

                Section("Subtitle Size") {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        #if os(iOS)
                        HStack {
                            Image(systemName: "textformat.size.smaller")
                            Slider(value: $model.subtitleScale, in: 0.5...2.5, step: 0.1)
                            Image(systemName: "textformat.size.larger")
                        }
                        #else
                        // tvOS: Slider isn't available, so use stepper buttons.
                        HStack(spacing: Theme.Spacing.lg) {
                            Button {
                                model.subtitleScale = max(0.5, model.subtitleScale - 0.1)
                            } label: {
                                Label("Smaller", systemImage: "textformat.size.smaller")
                            }
                            Text("\(Int(model.subtitleScale * 100))%")
                                .monospacedDigit()
                            Button {
                                model.subtitleScale = min(2.5, model.subtitleScale + 0.1)
                            } label: {
                                Label("Larger", systemImage: "textformat.size.larger")
                            }
                        }
                        #endif
                        Text("Preview").font(.system(size: 17 * model.subtitleScale))
                            .foregroundStyle(.secondary)
                    }
                }

                if model.audioTracks.count > 1 {
                    Section("Audio") {
                        ForEach(model.audioTracks) { track in
                            Button(track.name) { model.selectAudioTrack(track) }
                        }
                    }
                }
            }
            .navigationTitle("Audio & Subtitles")
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
    }

    // MARK: - Controls visibility

    private func revealControls() {
        controlsVisible = true
        scheduleHideControls()
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
            await MainActor.run { withAnimation { controlsVisible = false } }
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let total = Int(t)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }

    // MARK: - Drag / swipe to seek

    /// Updates the previewed scrub position from a horizontal drag translation.
    /// `width` is the available width when known (for proportional scrubbing); when
    /// nil we use a fixed sensitivity (about 90s of seek per full screen width).
    private func handleScrubChange(translation: CGFloat, width: CGFloat?) {
        guard model.duration > 0 else { return }
        if scrubTarget == nil { scrubStart = model.currentTime }
        let seconds: TimeInterval
        if let width, width > 0 {
            seconds = TimeInterval(translation / width) * model.duration
        } else {
            // Fixed sensitivity: ~0.25s per point of drag.
            seconds = TimeInterval(translation) * 0.25
        }
        let target = max(0, min(scrubStart + seconds, model.duration))
        scrubTarget = target
        revealControls()
    }

    /// Commits the previewed scrub position to the player and ends scrubbing.
    private func commitScrub() {
        if let target = scrubTarget {
            model.seek(to: target)
        }
        scrubTarget = nil
        scheduleHideControls()
    }

    /// A large centered readout of the target time while scrubbing.
    private func seekPreview(target: TimeInterval) -> some View {
        let delta = target - scrubStart
        let sign = delta >= 0 ? "+" : "−"
        return VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: delta >= 0 ? "goforward" : "gobackward")
                .font(.appFont(40, weight: .semibold))
            Text(timeString(target))
                .font(.appFont(34, weight: .bold))
                .monospacedDigit()
            Text("\(sign)\(timeString(abs(delta)))")
                .font(.appFont(20, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .foregroundStyle(.white)
        .padding(Theme.Spacing.xl)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .transition(.scale.combined(with: .opacity))
    }
}

// MARK: - VLC video surface

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
