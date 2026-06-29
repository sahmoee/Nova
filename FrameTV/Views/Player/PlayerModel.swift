//
//  PlayerModel.swift
//  FrameTV
//
//  The playback engine behind PlayerView. Responsibilities:
//    - Load and play an AVPlayerItem (direct URL or HLS).
//    - Resume from saved position; save progress every 10s via Task.sleep.
//    - Sideload subtitle tracks (SRT converted to VTT) and toggle them.
//    - Surface skip-intro / skip-outro windows and perform the skips.
//    - Detect completion to drive auto-play-next.
//    - Scrobble start/pause/stop to Trakt when enabled.
//

import SwiftUI
import AVKit
import Combine

@MainActor
final class PlayerModel: ObservableObject, StoppablePlayer {

    enum State: Equatable {
        case loading
        case ready
        case failed(String)
    }

    // Published UI state.
    @Published private(set) var state: State = .loading
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var activeSkip: SkipSegment?       // currently-offerable skip
    @Published private(set) var didFinish = false
    @Published private(set) var isBuffering = false            // mid-stream stall indicator
    @Published var showSubtitlePicker = false
    @Published private(set) var selectedSubtitleID: String?

    let player = AVPlayer()
    private(set) var item: MediaItem
    /// When true, playback starts from the beginning even if a resume position exists
    /// (set by the resume-or-restart prompt).
    var forceRestart = false

    // Injected dependencies.
    private weak var progressStore: PlaybackProgressStore?
    private var settings: SettingsStore?
    private var trakt: TraktClient?
    private var openSubtitles: OpenSubtitlesClient?

    // Internal.
    private var saveTask: Task<Void, Never>?
    private var timeObserver: Any?
    private var timeControlObserver: NSKeyValueObservation?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var lastScrobbleProgress: Double = -1
    private var hasScrobbledStart = false
    private var localSubtitleFiles: [String: URL] = [:]   // subtitle id -> local vtt file

    init(item: MediaItem) {
        self.item = item
    }

    func configure(progressStore: PlaybackProgressStore,
                   settings: SettingsStore,
                   trakt: TraktClient,
                   openSubtitles: OpenSubtitlesClient) {
        self.progressStore = progressStore
        self.settings = settings
        self.trakt = trakt
        self.openSubtitles = openSubtitles
    }

    // MARK: - Lifecycle

    func start() {
        // Ensure any other player is stopped — only one plays at a time.
        PlaybackCoordinator.shared.activate(self)
        state = .loading
        didFinish = false
        hasScrobbledStart = false

        let asset = AVURLAsset(url: item.playbackURL)
        let playerItem = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: playerItem)

        statusObservation = playerItem.observe(\.status, options: [.new]) { [weak self] pItem, _ in
            guard let self else { return }
            Task { @MainActor in
                switch pItem.status {
                case .readyToPlay: self.handleReady()
                case .failed:
                    let msg = pItem.error?.localizedDescription
                        ?? "The video couldn't be loaded. Check the source and your connection."
                    self.state = .failed(msg)
                default: break
                }
            }
        }

        // Completion.
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleDidFinish() }
        }
    }

    private func handleReady() {
        state = .ready
        // This engine successfully opened the file — remember it for next time.
        PlayerMemory.remember(.avPlayer, for: item)

        let dur = player.currentItem?.duration.seconds ?? 0
        duration = dur.isFinite ? dur : (item.duration ?? 0)

        let isLive = (item.sourceType == .liveTV)

        // Resume (never for live channels — there's no fixed timeline). If the user
        // chose Restart at the prompt, forceRestart skips the resume seek.
        if !isLive, !forceRestart,
           (settings?.resumePlaybackEnabled ?? true),
           let resume = progressStore?.resumePosition(for: item.id) {
            player.seek(to: CMTime(seconds: resume, preferredTimescale: 600)) { [weak self] _ in
                self?.player.play()
            }
        } else {
            player.play()
        }

        installTimeObserver()
        if !isLive {
            startSaveLoop()
            scrobble(.start)
        }
        NowPlayingStore.shared.begin(item)

        // Auto-load preferred subtitle if enabled.
        if settings?.subtitlesEnabled == true {
            Task { await autoEnablePreferredSubtitle() }
        }
    }

    // MARK: - Time observation (drives skip windows + scrobble)

    private func installTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        // The observer is delivered on .main, but the closure isn't statically
        // main-actor isolated, so hop explicitly to mutate main-actor state safely.
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let t = time.seconds
            guard t.isFinite else { return }
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = t
                self.updateActiveSkip(at: t)
                let frac = self.duration > 0 ? t / self.duration : 0
                NowPlayingStore.shared.update(progress: frac,
                                              isPlaying: self.player.timeControlStatus == .playing)
            }
        }

        // Track buffering vs playing for a mid-stream stall indicator.
        timeControlObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                self?.isBuffering = (player.timeControlStatus == .waitingToPlayAtSpecifiedRate)
            }
        }
    }

    private func updateActiveSkip(at t: TimeInterval) {
        guard let settings else { activeSkip = nil; return }

        // Find a segment containing the current time, respecting per-kind toggles.
        let seg = item.skipSegments.first { s in
            switch s.kind {
            case .intro, .recap: return settings.skipIntroEnabled && s.contains(t)
            case .outro:        return settings.skipOutroEnabled && s.contains(t)
            }
        }

        // Auto-skip intro if configured.
        if let seg, seg.kind == .intro, settings.autoSkipIntro {
            performSkip(seg)
            activeSkip = nil
            return
        }

        activeSkip = seg
    }

    /// Skips to the end of the given segment.
    func performSkip(_ segment: SkipSegment) {
        let target = CMTime(seconds: segment.end + 0.1, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        activeSkip = nil
    }

    func skipActiveSegment() {
        if let activeSkip { performSkip(activeSkip) }
    }

    // MARK: - Progress saving + scrobble

    private func startSaveLoop() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard let self else { return }
                await self.saveProgress()
                self.scrobbleProgressIfNeeded()
            }
        }
    }

    private func saveProgress() async {
        guard state == .ready else { return }
        let current = player.currentTime().seconds
        let dur = player.currentItem?.duration.seconds
        let validDuration = (dur?.isFinite == true) ? dur : nil
        guard current.isFinite, current > 0 else { return }
        progressStore?.save(position: current, duration: validDuration, for: item.id)
    }

    private var progressPercent: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration * 100, 0), 100)
    }

    /// Seconds remaining in the current item (0 when unknown).
    var remainingTime: TimeInterval {
        guard duration > 0 else { return 0 }
        return max(duration - currentTime, 0)
    }

    /// True in the final stretch of playback, used to surface the up-next card.
    func isNearEnd(within seconds: TimeInterval) -> Bool {
        duration > 0 && remainingTime <= seconds && remainingTime > 0
    }

    private func scrobbleProgressIfNeeded() {
        // Trakt rate-limits scrobbles; only send on meaningful change.
        let pct = progressPercent
        if abs(pct - lastScrobbleProgress) >= 5 {
            lastScrobbleProgress = pct
            scrobble(.pause)   // "pause" updates progress without marking complete
        }
    }

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

    // MARK: - Completion

    private func handleDidFinish() {
        // Guard against spurious end events on very short or failed items: only treat
        // as a real finish if the item had a sensible duration and we actually played
        // most of it. This prevents auto-play-next from hijacking when an item reports
        // end immediately at position zero.
        let dur = player.currentItem?.duration.seconds ?? 0
        let pos = player.currentTime().seconds
        guard dur.isFinite, dur > 1, pos >= dur * 0.85 else { return }
        progressStore?.save(position: dur, duration: dur, for: item.id)
        scrobble(.stop)
        didFinish = true
    }

    // MARK: - Subtitles

    /// Adds available subtitle tracks to the player by sideloading their files.
    /// AVPlayer can't add remote text tracks to a non-HLS asset directly, so we
    /// download + convert to VTT and expose them through the picker; selecting one
    /// rebuilds the player item with the local subtitle as a media selection where
    /// supported, otherwise renders via the legible-text overlay.
    var availableSubtitles: [SubtitleTrack] { item.subtitles }

    func selectSubtitle(_ track: SubtitleTrack?) {
        selectedSubtitleID = track?.id
        showSubtitlePicker = false

        // For embedded tracks, use AVMediaSelection.
        if let track, track.isEmbedded {
            selectEmbeddedLegibleOption(matching: track)
            return
        }

        // For external tracks, ensure the file is downloaded, then apply.
        guard let track else {
            applyExternalSubtitle(localURL: nil)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            if let local = await self.ensureLocalSubtitle(track) {
                self.applyExternalSubtitle(localURL: local)
            }
        }
    }

    /// Downloads (if needed) and converts a subtitle to a local VTT file.
    private func ensureLocalSubtitle(_ track: SubtitleTrack) async -> URL? {
        if let cached = localSubtitleFiles[track.id] { return cached }

        // Resolve a URL: OpenSubtitles tracks need a download request first.
        var sourceURL = track.url
        if sourceURL == nil, track.id.hasPrefix("os:"),
           let fileID = Int(track.id.dropFirst(3)) {
            sourceURL = try? await openSubtitles?.requestDownload(fileID: fileID)
        }
        guard let sourceURL else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: sourceURL)
            let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) ?? ""
            let vtt = SubtitleConverter.srtToVTT(text)

            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("subtitles", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let fileURL = dir.appendingPathComponent("\(track.id.replacingOccurrences(of: ":", with: "_")).vtt")
            try vtt.data(using: .utf8)?.write(to: fileURL, options: [.atomic])
            localSubtitleFiles[track.id] = fileURL
            return fileURL
        } catch {
            return nil
        }
    }

    /// Applies an external subtitle by rebuilding the composition. Seeks back to
    /// the current position so playback continues seamlessly.
    private func applyExternalSubtitle(localURL: URL?) {
        let resumeAt = player.currentTime()

        guard let localURL else {
            // Turning subtitles off: just rebuild from the plain asset.
            rebuildItem(with: nil, resumeAt: resumeAt)
            return
        }
        rebuildItem(with: localURL, resumeAt: resumeAt)
    }

    /// Rebuilds the AVPlayerItem, optionally merging a local subtitle track via
    /// AVMutableComposition so it shows as a selectable legible track.
    private func rebuildItem(with subtitleURL: URL?, resumeAt: CMTime) {
        let videoAsset = AVURLAsset(url: item.playbackURL)

        guard let subtitleURL else {
            let newItem = AVPlayerItem(asset: videoAsset)
            swapItem(newItem, resumeAt: resumeAt)
            return
        }

        let composition = AVMutableComposition()
        let subtitleAsset = AVURLAsset(url: subtitleURL)

        Task { [weak self] in
            guard let self else { return }
            do {
                // Video + audio tracks.
                let duration = try await videoAsset.load(.duration)
                let range = CMTimeRange(start: .zero, duration: duration)

                let vTracks = try await videoAsset.loadTracks(withMediaType: .video)
                if let v = vTracks.first,
                   let compV = composition.addMutableTrack(withMediaType: .video,
                                                           preferredTrackID: kCMPersistentTrackID_Invalid) {
                    try compV.insertTimeRange(range, of: v, at: .zero)
                }
                let aTracks = try await videoAsset.loadTracks(withMediaType: .audio)
                if let a = aTracks.first,
                   let compA = composition.addMutableTrack(withMediaType: .audio,
                                                           preferredTrackID: kCMPersistentTrackID_Invalid) {
                    try compA.insertTimeRange(range, of: a, at: .zero)
                }
                // Subtitle (text) track.
                let tTracks = try await subtitleAsset.loadTracks(withMediaType: .text)
                if let t = tTracks.first,
                   let compT = composition.addMutableTrack(withMediaType: .text,
                                                           preferredTrackID: kCMPersistentTrackID_Invalid) {
                    try compT.insertTimeRange(range, of: t, at: .zero)
                }

                let newItem = AVPlayerItem(asset: composition)
                await MainActor.run { self.swapItem(newItem, resumeAt: resumeAt) }
            } catch {
                // If compositing fails, fall back to the plain video so playback
                // is never broken by a subtitle issue.
                let newItem = AVPlayerItem(asset: videoAsset)
                await MainActor.run { self.swapItem(newItem, resumeAt: resumeAt) }
            }
        }
    }

    private func swapItem(_ newItem: AVPlayerItem, resumeAt: CMTime) {
        // Re-observe the new item and reinstall the end notification.
        statusObservation?.invalidate()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }

        player.replaceCurrentItem(with: newItem)
        statusObservation = newItem.observe(\.status, options: [.new]) { [weak self] pItem, _ in
            guard let self else { return }
            Task { @MainActor in
                if pItem.status == .readyToPlay {
                    self.player.seek(to: resumeAt, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                        self.player.play()
                    }
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: newItem, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleDidFinish() }
        }
    }

    private func selectEmbeddedLegibleOption(matching track: SubtitleTrack) {
        guard let playerItem = player.currentItem else { return }
        Task {
            guard let group = try? await playerItem.asset.loadMediaSelectionGroup(for: .legible) else { return }
            let options = group.options
            if let match = options.first(where: { opt in
                opt.locale?.identifier.hasPrefix(track.language) == true
                || opt.displayName.localizedCaseInsensitiveContains(track.languageDisplay)
            }) {
                playerItem.select(match, in: group)
            }
        }
    }

    private func autoEnablePreferredSubtitle() async {
        guard let preferred = settings?.subtitleLanguage else { return }
        if let match = item.subtitles.first(where: { $0.language.hasPrefix(preferred) }) {
            await MainActor.run { self.selectSubtitle(match) }
        }
    }

    // MARK: - Transport

    func retry() {
        teardownObservers()
        start()
    }

    func play() { player.play() }
    func pause() { player.pause(); scrobble(.pause) }

    func stopAndSave() {
        PlaybackCoordinator.shared.resign(self)
        saveTask?.cancel(); saveTask = nil
        Task { await saveProgress() }
        scrobble(.stop)
        player.pause()
        NowPlayingStore.shared.clear()
        teardownObservers()
    }

    private func teardownObservers() {
        statusObservation?.invalidate(); statusObservation = nil
        timeControlObserver?.invalidate(); timeControlObserver = nil
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }
}
