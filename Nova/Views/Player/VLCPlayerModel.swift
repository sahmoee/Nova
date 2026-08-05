//
//  VLCPlayerModel.swift
//  Nova
//
//  A VLCKit-backed player used for formats AVPlayer can't open (MKV, AVI, etc.).
//  VLCKit decodes virtually every container/codec. This model mirrors the parts of
//  the AVPlayer model the UI needs — state, currentTime, duration, buffering — and
//  handles resume + progress saving + Trakt scrobbling, plus embedded subtitle and
//  audio track selection (which VLC exposes directly, unlike AVPlayer).
//
//  Format routing lives in PlayerView: MP4/HLS keep the AVPlayer path; everything
//  else comes here.
//

import Foundation
import SwiftUI
#if canImport(VLCKitSPM)
import VLCKitSPM
#endif

@MainActor
final class VLCPlayerModel: NSObject, ObservableObject, StoppablePlayer {

    enum State: Equatable {
        case loading
        case ready
        case failed(String)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isBuffering = false
    @Published private(set) var isPlaying = false
    @Published private(set) var didFinish = false

    // Track selection exposed to the UI.
    @Published private(set) var subtitleTracks: [VLCTrack] = []
    @Published private(set) var audioTracks: [VLCTrack] = []
    @Published private(set) var externalSubtitleTracks: [SubtitleTrack]
    @Published private(set) var selectedExternalSubtitleID: String?
    @Published private(set) var isLoadingExternalSubtitles = false
    @Published private(set) var subtitleStatusMessage: String?
    @Published var showSubtitlePicker = false

    struct VLCTrack: Identifiable, Hashable {
        let id: Int          // VLC track index
        let name: String
    }

    let item: MediaItem

    private var progressStore: PlaybackProgressStore?
    private var settings: SettingsStore?
    private var trakt: TraktClient?
    private var catalog: CatalogService?
    private var openSubtitles: OpenSubtitlesClient?
    /// Optional: lets the player persist a subtitle timing offset back to the item.
    private var libraryStore: LibraryStore?

    private var saveTask: Task<Void, Never>?
    private var hasScrobbledStart = false
    private var lastScrobbleProgress: Double = 0
    private var didApplyResume = false
    private var didAttemptAutomaticSubtitles = false
    private var localSubtitleFiles: [String: URL] = [:]
    /// When true, the resume seek is skipped so playback starts from the beginning
    /// (set by the "Start from beginning" choice in the resume prompt).
    var forceRestart = false

    /// The saved resume position for this item, if resume is enabled and it's past the
    /// meaningful checkpoint threshold. Used by the view to decide whether to show the resume prompt.
    var savedResumePosition: TimeInterval? {
        guard item.sourceType != .liveTV,
              (settings?.resumePlaybackEnabled ?? true),
              let resume = progressStore?.resumePosition(for: item) else { return nil }
        return resume
    }

    #if canImport(VLCKitSPM)
    let mediaPlayer = VLCMediaPlayer()
    #endif

    init(item: MediaItem) {
        self.item = item
        self.externalSubtitleTracks = item.subtitles
        super.init()
    }

    func configure(progressStore: PlaybackProgressStore,
                   settings: SettingsStore,
                   trakt: TraktClient,
                   catalog: CatalogService,
                   openSubtitles: OpenSubtitlesClient,
                   libraryStore: LibraryStore? = nil) {
        self.progressStore = progressStore
        self.settings = settings
        self.trakt = trakt
        self.catalog = catalog
        self.openSubtitles = openSubtitles
        self.libraryStore = libraryStore
        // Seed the live delay from this title's remembered offset.
        subtitleDelay = item.subtitleOffset
    }

    // MARK: - Lifecycle

    private var isActive = false

    func start() {
        #if canImport(VLCKitSPM)
        // Don't restart if already running (guards against duplicate start calls).
        guard !isActive else { return }
        isActive = true
        // Ensure any other player is stopped — only one plays at a time.
        PlaybackCoordinator.shared.activate(self)
        state = .loading
        didFinish = false
        hasScrobbledStart = false
        currentTime = 0
        duration = 0
        isBuffering = false
        isPlaying = false
        didApplyResume = false
        didAttemptAutomaticSubtitles = false

        let media = VLCMedia(url: item.playbackURL)
        // Apply the user's built-in player profile (network cache size, hardware
        // decoding preference). These map to libVLC media options.
        if let profile = settings?.builtInPlayer {
            if let cacheMs = profile.vlcNetworkCacheMs {
                media.addOption("--network-caching=\(cacheMs)")
                media.addOption("--file-caching=\(cacheMs)")
            }
            if profile.prefersHardwareDecoding {
                media.addOption("--codec=videotoolbox")
            }
        }
        mediaPlayer.media = media
        mediaPlayer.delegate = self
        mediaPlayer.play()
        let saved = progressStore?.resumePosition(for: item) ?? 0
        let initialProgress = (item.duration ?? 0) > 0 ? saved / (item.duration ?? 1) : 0
        NowPlayingStore.shared.begin(item, initialProgress: initialProgress)
        // VLC reports readiness asynchronously via delegate callbacks.
        #else
        state = .failed("VLC playback engine unavailable in this build.")
        #endif
    }

    /// Used by the retry button to force a fresh start after a failure.
    func restart() {
        isActive = false
        start()
    }

    func stopAndSave() {
        // Idempotent: the back button and onDisappear can both call this.
        guard isActive else { return }
        isActive = false
        PlaybackCoordinator.shared.resign(self)
        saveTask?.cancel(); saveTask = nil
        checkpointProgress()
        scrobble(.stop)
        NowPlayingStore.shared.clear()
        #if canImport(VLCKitSPM)
        mediaPlayer.stop()
        mediaPlayer.delegate = nil
        #endif
    }

    /// The user left the player screen without explicitly stopping. Save position and
    /// stop the pipeline, but keep the Now Playing / Resume bar (minimize) so they can
    /// jump back in. Tapping the bar reopens the player and resumes from saved time.
    func minimizeAndSave() {
        guard isActive else { return }
        isActive = false
        PlaybackCoordinator.shared.resign(self)
        saveTask?.cancel(); saveTask = nil
        checkpointProgress()
        scrobble(.pause)
        NowPlayingStore.shared.minimize()
        #if canImport(VLCKitSPM)
        mediaPlayer.stop()
        mediaPlayer.delegate = nil
        #endif
    }

    // MARK: - Controls

    func togglePlayPause() {
        #if canImport(VLCKitSPM)
        if mediaPlayer.isPlaying {
            checkpointProgress()
            mediaPlayer.pause()
            scrobble(.pause)
        } else {
            mediaPlayer.play()
        }
        #endif
    }

    func seek(to seconds: TimeInterval) {
        #if canImport(VLCKitSPM)
        let upperBound = duration > 0 ? duration : seconds
        let clamped = max(0, min(seconds, upperBound))
        // Setting VLC's millisecond clock preserves the exact saved timestamp; using
        // normalized `position` can round noticeably on long movies.
        mediaPlayer.time = VLCTime(int: Int32(clamped * 1_000))
        currentTime = clamped
        #endif
    }

    func skipForward(_ secs: Int = 15) {
        #if canImport(VLCKitSPM)
        mediaPlayer.jumpForward(Int32(secs))
        #endif
    }

    func skipBackward(_ secs: Int = 15) {
        #if canImport(VLCKitSPM)
        mediaPlayer.jumpBackward(Int32(secs))
        #endif
    }

    var remainingTime: TimeInterval { max(duration - currentTime, 0) }

    // MARK: - Subtitle / audio tracks

    func selectSubtitleTrack(_ track: VLCTrack?) {
        #if canImport(VLCKitSPM)
        // -1 disables subtitles in VLC. Selecting an embedded track replaces the
        // provider selection indicator so the picker reflects what is actually live.
        mediaPlayer.currentVideoSubTitleIndex = Int32(track?.id ?? -1)
        selectedExternalSubtitleID = nil
        showSubtitlePicker = false
        #endif
    }

    func disableSubtitles() {
        #if canImport(VLCKitSPM)
        mediaPlayer.currentVideoSubTitleIndex = -1
        selectedExternalSubtitleID = nil
        subtitleStatusMessage = "Subtitles are off."
        showSubtitlePicker = false
        #endif
    }

    func selectAudioTrack(_ track: VLCTrack) {
        #if canImport(VLCKitSPM)
        mediaPlayer.currentAudioTrackIndex = Int32(track.id)
        #endif
    }

    /// Subtitle text scale. 1.0 is default; larger is bigger text. Persisted so the
    /// choice carries across playback sessions.
    @Published var subtitleScale: Double = UserDefaults.standard.object(forKey: "player.subtitleScale") as? Double ?? 1.0 {
        didSet {
            UserDefaults.standard.set(subtitleScale, forKey: "player.subtitleScale")
            applySubtitleScale()
        }
    }

    func applySubtitleScale() {
        #if canImport(VLCKitSPM)
        // VLCMediaPlayer.setTextRendererFontSize is not exposed on all builds, so we
        // guard the call. Larger scale => bigger text; VLC font size is in points.
        // Map scale 0.5...2.0 onto roughly 12...48pt.
        let size = NSNumber(value: Int(16 * subtitleScale * 1.5))
        if mediaPlayer.responds(to: Selector(("setTextRendererFontSize:"))) {
            mediaPlayer.perform(Selector(("setTextRendererFontSize:")), with: size)
        }
        #endif
    }

    /// Live subtitle timing offset in seconds (+ = subtitles appear later). Applies to
    /// VLC immediately and remembers the value on the item via the library store.
    @Published var subtitleDelay: Double = 0 {
        didSet {
            #if canImport(VLCKitSPM)
            mediaPlayer.currentVideoSubTitleDelay = Int(subtitleDelay * 1_000_000)
            #endif
            libraryStore?.setSubtitleOffset(subtitleDelay, for: item)
        }
    }

    /// Loads an external subtitle file (e.g. a .srt the user picked) and selects it.
    func addExternalSubtitle(_ url: URL) {
        #if canImport(VLCKitSPM)
        mediaPlayer.addPlaybackSlave(url, type: .subtitle, enforce: true)
        // VLCKit publishes the new track asynchronously after the slave is attached.
        // Refresh once immediately and once after a brief registration window.
        refreshTracks()
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.refreshTracks()
        }
        #endif
    }

    /// Searches enabled subtitle add-ons and exposes their results in the picker.
    /// When requested at startup, the preferred language is downloaded and selected.
    func refreshExternalSubtitles(autoSelectPreferred: Bool = false) async {
        guard !isLoadingExternalSubtitles else { return }
        guard let contentID = item.contentID, let catalog else {
            subtitleStatusMessage = externalSubtitleTracks.isEmpty
                ? "This item has no catalog ID for subtitle lookup."
                : nil
            if autoSelectPreferred { await autoSelectPreferredExternalSubtitle() }
            return
        }

        isLoadingExternalSubtitles = true
        subtitleStatusMessage = "Searching subtitle add-ons…"
        let fetched = await catalog.subtitles(for: contentID, episode: item.episode)
        mergeExternalSubtitleTracks(fetched)
        isLoadingExternalSubtitles = false
        subtitleStatusMessage = fetched.isEmpty
            ? (externalSubtitleTracks.isEmpty ? "No subtitle add-on returned a match." : "No new subtitles found.")
            : "Found \(fetched.count) subtitle option\(fetched.count == 1 ? "" : "s")."

        if autoSelectPreferred, !didAttemptAutomaticSubtitles {
            didAttemptAutomaticSubtitles = true
            await autoSelectPreferredExternalSubtitle()
        }
    }

    func selectExternalSubtitle(_ track: SubtitleTrack) {
        selectedExternalSubtitleID = track.id
        Task { await downloadAndAttachSubtitle(track) }
    }

    private func mergeExternalSubtitleTracks(_ tracks: [SubtitleTrack]) {
        var seen = Set<String>()
        externalSubtitleTracks = (externalSubtitleTracks + tracks).filter { track in
            let key = "\(track.language.lowercased())|\(track.url?.absoluteString ?? track.id)"
            return seen.insert(key).inserted
        }
    }

    private func autoSelectPreferredExternalSubtitle() async {
        guard settings?.subtitlesEnabled == true,
              let preferred = settings?.subtitleLanguage,
              let match = externalSubtitleTracks.first(where: {
                  $0.matchesPreferredLanguage(preferred)
              }) else { return }
        selectedExternalSubtitleID = match.id
        await downloadAndAttachSubtitle(match)
    }

    private func downloadAndAttachSubtitle(_ track: SubtitleTrack) async {
        isLoadingExternalSubtitles = true
        defer { isLoadingExternalSubtitles = false }

        if let cached = localSubtitleFiles[track.id] {
            addExternalSubtitle(cached)
            subtitleStatusMessage = "Using \(track.languageDisplay) subtitles from \(track.source)."
            showSubtitlePicker = false
            return
        }

        subtitleStatusMessage = "Downloading \(track.languageDisplay) subtitles…"
        var sourceURL = track.url
        if sourceURL == nil, track.id.hasPrefix("os:"),
           let fileID = Int(track.id.dropFirst(3)) {
            sourceURL = try? await openSubtitles?.requestDownload(fileID: fileID)
        }
        guard let sourceURL else {
            subtitleStatusMessage = "The selected subtitle could not be downloaded."
            return
        }

        do {
            let (data, response) = try await AppNetworking.shared.data(from: sourceURL)
            let suggested = response.suggestedFilename ?? sourceURL.lastPathComponent
            let ext = URL(fileURLWithPath: suggested).pathExtension.isEmpty
                ? (sourceURL.pathExtension.isEmpty ? "srt" : sourceURL.pathExtension)
                : URL(fileURLWithPath: suggested).pathExtension
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("vlc_subtitles", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let safeID = track.id.replacingOccurrences(of: ":", with: "_")
                .replacingOccurrences(of: "/", with: "_")
            let local = dir.appendingPathComponent("\(safeID).\(ext)")
            try data.write(to: local, options: [.atomic])
            localSubtitleFiles[track.id] = local
            addExternalSubtitle(local)
            subtitleStatusMessage = "Using \(track.languageDisplay) subtitles from \(track.source)."
            showSubtitlePicker = false
        } catch {
            subtitleStatusMessage = "The selected subtitle could not be downloaded."
        }
    }

    /// Whether the video fills the screen (cropping) vs. fits with letterboxing.
    /// The actual fill is applied at the SwiftUI view layer (a scale on the player
    /// surface), which works on any VLCKit build and can't crash — unlike VLCKit's
    /// videoCropGeometry, which isn't key-value-coding compliant on this build.
    @Published var fillScreen: Bool = false

    // MARK: - Progress

    private func startSaveLoop() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run { self?.checkpointProgress() }
            }
        }
    }

    func checkpointProgress() {
        guard item.sourceType != .liveTV, duration > 0, currentTime > 0 else { return }
        progressStore?.save(position: currentTime, duration: duration, for: item)
        NowPlayingStore.shared.update(progress: currentTime / duration, isPlaying: isPlaying)
    }

    private var progressPercent: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration * 100, 0), 100)
    }

    private func applyResumeIfNeeded() {
        guard !didApplyResume else { return }
        didApplyResume = true
        // Live channels have no fixed timeline — never resume or save a position.
        guard item.sourceType != .liveTV else { return }
        #if canImport(VLCKitSPM)
        // Apply the user's default playback speed.
        if let speed = settings?.playbackSpeed, speed > 0 {
            mediaPlayer.rate = Float(speed)
        }
        // Apply this title's remembered subtitle timing offset (seconds -> microseconds).
        if item.subtitleOffset != 0 {
            mediaPlayer.currentVideoSubTitleDelay = Int(item.subtitleOffset * 1_000_000)
        }
        #endif
        // If the user chose "Start from beginning" in the resume prompt, skip the seek.
        guard !forceRestart else { return }
        if (settings?.resumePlaybackEnabled ?? true),
           let resume = progressStore?.resumePosition(for: item) {
            seek(to: resume)
        }
    }

    /// Updates the live subtitle delay and remembers it for this title.
    func setSubtitleOffset(_ seconds: Double, progressStore: PlaybackProgressStore? = nil) {
        #if canImport(VLCKitSPM)
        mediaPlayer.currentVideoSubTitleDelay = Int(seconds * 1_000_000)
        #endif
    }

    /// Live playback-speed change (e.g. from a player control).
    func setRate(_ rate: Double) {
        #if canImport(VLCKitSPM)
        mediaPlayer.rate = Float(max(0.25, min(rate, 3.0)))
        #endif
    }

    // MARK: - Trakt

    private func scrobble(_ action: ScrobbleAction) {
        guard settings?.traktScrobblingEnabled == true,
              let trakt, let contentID = item.contentID else { return }
        if action == .start { hasScrobbledStart = true }
        let pct = progressPercent
        let ep = item.episode
        Task.detached {
            await trakt.scrobble(action: action, contentID: contentID, episode: ep, progress: pct)
        }
    }

    private func scrobbleProgressIfNeeded() {
        let pct = progressPercent
        if abs(pct - lastScrobbleProgress) >= 5 {
            lastScrobbleProgress = pct
            scrobble(.pause)
        }
    }

    private func refreshTracks() {
        #if canImport(VLCKitSPM)
        // Build subtitle + audio track lists from VLC's indices/names.
        func tracks(indices: [Any]?, names: [Any]?) -> [VLCTrack] {
            guard let indices = indices as? [NSNumber],
                  let names = names as? [String] else { return [] }
            var out: [VLCTrack] = []
            for (i, idx) in indices.enumerated() where i < names.count {
                let id = idx.intValue
                if id < 0 { continue }   // skip the "Disable" pseudo-track
                out.append(VLCTrack(id: id, name: names[i]))
            }
            return out
        }
        subtitleTracks = tracks(indices: mediaPlayer.videoSubTitlesIndexes,
                                names: mediaPlayer.videoSubTitlesNames)
        audioTracks = tracks(indices: mediaPlayer.audioTrackIndexes,
                             names: mediaPlayer.audioTrackNames)
        #endif
    }
}

#if canImport(VLCKitSPM)
extension VLCPlayerModel: VLCMediaPlayerDelegate {

    nonisolated func mediaPlayerStateChanged(_ aNotification: Notification) {
        Task { @MainActor in
            switch mediaPlayer.state {
            case .opening:
                // Initial open before any frames — show the spinner only while still loading.
                if self.state == .loading { self.isBuffering = true }
            case .buffering:
                // VLC emits .buffering repeatedly even mid-playback. Only treat it as
                // buffering if playback isn't currently advancing; mediaPlayerTimeChanged
                // clears it as soon as time moves.
                if !mediaPlayer.isPlaying { self.isBuffering = true }
                if self.state == .loading, mediaPlayer.isPlaying {
                    self.state = .ready
                    self.markReady()
                }
            case .playing:
                self.isBuffering = false
                self.isPlaying = true
                if self.state == .loading {
                    self.state = .ready
                    self.markReady()
                }
                // This engine successfully opened the file — remember it for next time.
                PlayerMemory.remember(.vlc, for: self.item)
                self.refreshTracks()
            case .paused:
                self.isBuffering = false
                self.isPlaying = false
                self.checkpointProgress()
            case .stopped:
                self.isBuffering = false
                self.isPlaying = false
            case .ended:
                self.isBuffering = false
                self.handleEnded()
            case .error:
                self.isBuffering = false
                self.state = .failed("VLC couldn't play this stream.")
            default:
                break
            }
        }
    }

    @MainActor
    private func markReady() {
        applyResumeIfNeeded()
        startSaveLoop()
        scrobble(.start)
        applySubtitleScale()
        if settings?.subtitlesEnabled == true {
            if settings?.autoDownloadSubtitles == true {
                Task { await refreshExternalSubtitles(autoSelectPreferred: true) }
            } else {
                Task { await autoSelectPreferredExternalSubtitle() }
            }
        }
    }

    nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
        Task { @MainActor in
            let ms = mediaPlayer.time.intValue          // current time in ms
            self.currentTime = TimeInterval(ms) / 1000.0
            // Time is advancing, so we're playing, not buffering. This is the reliable
            // signal to clear a spinner that VLC's buffering state left stuck on.
            if self.isBuffering { self.isBuffering = false }
            if self.state == .loading {
                self.state = .ready
                self.markReady()
            }
            // VLC length becomes known shortly after play starts.
            let lengthMs = mediaPlayer.media?.length.intValue ?? 0
            if lengthMs > 0 { self.duration = TimeInterval(lengthMs) / 1000.0 }
            self.scrobbleProgressIfNeeded()
            // Feed the Now Playing mini-bar.
            let frac = self.duration > 0 ? self.currentTime / self.duration : 0
            NowPlayingStore.shared.update(progress: frac, isPlaying: self.isPlaying)
        }
    }

    @MainActor
    private func handleEnded() {
        // Only treat as a real finish if we actually played most of a sensibly-long
        // item, so a quick failure or zero-length stream can't trigger auto-play-next.
        guard duration > 1, currentTime >= duration * 0.85 else { return }
        progressStore?.save(position: duration, duration: duration, for: item)
        scrobble(.stop)
        didFinish = true
    }
}
#endif
