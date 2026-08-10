//
//  PlayerModel.swift
//  Nova
//
//  The playback engine behind PlayerView. Responsibilities:
//    - Load and play an AVPlayerItem (direct URL or HLS).
//    - Resume from the saved position; checkpoint every 5s and on pause/exit.
//    - Discover add-on subtitles, normalize SRT/VTT, and render timed text.
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
    @Published private(set) var subtitleTracks: [SubtitleTrack]
    @Published private(set) var isLoadingSubtitles = false
    @Published private(set) var subtitleStatusMessage: String?
    @Published private(set) var activeSubtitleText: String?

    let player = AVPlayer()
    private(set) var item: MediaItem
    /// When true, playback starts from the beginning even if a resume position exists
    /// (set by the resume-or-restart prompt).
    var forceRestart = false

    // Injected dependencies.
    private weak var progressStore: PlaybackProgressStore?
    private var settings: SettingsStore?
    private var trackers: TrackingHub?
    private var openSubtitles: OpenSubtitlesClient?
    private var catalog: CatalogService?

    // Internal.
    private var saveTask: Task<Void, Never>?
    private var timeObserver: Any?
    private var timeControlObserver: NSKeyValueObservation?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var lastScrobbleProgress: Double = -1
    private var hasScrobbledStart = false
    private var localSubtitleFiles: [String: URL] = [:]   // subtitle id -> local vtt file
    private var lastTimeControlStatus: AVPlayer.TimeControlStatus?
    private var didAttemptAutomaticSubtitles = false
    private var externalSubtitleCues: [SubtitleCue] = []

    private struct SubtitleCue: Sendable {
        let start: TimeInterval
        let end: TimeInterval
        let text: String
    }

    init(item: MediaItem) {
        self.item = item
        self.subtitleTracks = item.subtitles
    }

    func configure(progressStore: PlaybackProgressStore,
                   settings: SettingsStore,
                   trackers: TrackingHub,
                   openSubtitles: OpenSubtitlesClient,
                   catalog: CatalogService) {
        self.progressStore = progressStore
        self.settings = settings
        self.trackers = trackers
        self.openSubtitles = openSubtitles
        self.catalog = catalog
    }

    // MARK: - Lifecycle

    func start() {
        // Ensure any other player is stopped — only one plays at a time.
        PlaybackCoordinator.shared.activate(self)
        state = .loading
        didFinish = false
        hasScrobbledStart = false
        currentTime = 0
        duration = 0
        activeSkip = nil
        isBuffering = false
        lastTimeControlStatus = nil
        didAttemptAutomaticSubtitles = false
        externalSubtitleCues = []
        activeSubtitleText = nil

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
           let resume = progressStore?.resumePosition(for: item) {
            currentTime = resume
            let target = CMTime(seconds: resume, preferredTimescale: 1_000)
            // Zero tolerance requests the exact saved timestamp instead of allowing
            // AVPlayer to jump backward to a nearby keyframe.
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
                guard finished else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.currentTime = resume
                    self.player.play()
                    self.applyPlaybackSpeed()
                }
            }
        } else {
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            player.play()
            applyPlaybackSpeed()
        }

        installTimeObserver()
        if !isLive {
            startSaveLoop()
            scrobble(.start)
        }
        let initialProgress = duration > 0 ? currentTime / duration : 0
        NowPlayingStore.shared.begin(item, initialProgress: initialProgress)

        // Skip markers are enrichment, never a prerequisite for first frame.
        Task { [weak self] in
            guard let self, let catalog = self.catalog else { return }
            let segments = await catalog.skipSegments(for: self.item)
            self.item.skipSegments = segments
        }

        // Query enabled subtitle addons as playback starts, then download and select
        // the preferred language. The picker can repeat this on demand.
        if settings?.subtitlesEnabled == true, !isLive {
            if settings?.autoDownloadSubtitles == true {
                Task { await refreshSubtitlesFromProviders(autoSelectPreferred: true) }
            } else {
                Task { await autoEnablePreferredSubtitle() }
            }
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
                self.updateExternalSubtitle(at: t)
                let frac = self.duration > 0 ? t / self.duration : 0
                NowPlayingStore.shared.update(progress: frac,
                                              isPlaying: self.player.timeControlStatus == .playing)
            }
        }

        // Track buffering vs playing for a mid-stream stall indicator.
        timeControlObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self else { return }
                let status = player.timeControlStatus
                self.isBuffering = (status == .waitingToPlayAtSpecifiedRate)
                NowPlayingStore.shared.isPlaying = (status == .playing)
                // Native AVPlayer controls pause without calling PlayerModel.pause().
                // Save immediately on every transition away from playing so Resume is
                // the exact point where the viewer stopped, not the last 10-second tick.
                if self.lastTimeControlStatus == .playing && status == .paused {
                    self.checkpointProgress()
                    self.scrobble(.pause)
                }
                self.lastTimeControlStatus = status
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
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self else { return }
                self.checkpointProgress()
                self.scrobbleProgressIfNeeded()
            }
        }
    }

    /// Persists an immediate playback checkpoint. Safe to call from pause, scene
    /// transitions, minimize, stop, and the periodic save loop.
    func checkpointProgress() {
        guard state == .ready, item.sourceType != .liveTV else { return }
        let liveCurrent = player.currentTime().seconds
        let current = liveCurrent.isFinite ? liveCurrent : currentTime
        let itemDuration = player.currentItem?.duration.seconds
        let validDuration = (itemDuration?.isFinite == true && (itemDuration ?? 0) > 0)
            ? itemDuration : (duration > 0 ? duration : item.duration)
        guard current.isFinite, current > 0 else { return }
        currentTime = current
        progressStore?.save(position: current, duration: validDuration, for: item)
        if let validDuration, validDuration > 0 {
            NowPlayingStore.shared.update(progress: current / validDuration,
                                          isPlaying: player.timeControlStatus == .playing)
        }
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
              let trackers, let contentID = item.contentID else { return }
        if action == .start { hasScrobbledStart = true }
        let pct = progressPercent
        let ep = item.episode
        Task.detached {
            await trackers.scrobble(action: action, contentID: contentID, episode: ep, progress: pct)
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
        progressStore?.save(position: dur, duration: dur, for: item)
        scrobble(.stop)
        didFinish = true
    }

    // MARK: - Subtitles

    /// Available embedded and provider subtitle tracks. External files are downloaded,
    /// normalized to WebVTT, and rendered as timed text above native player controls.
    var availableSubtitles: [SubtitleTrack] { subtitleTracks }

    /// Requeries enabled Stremio subtitle addons (plus OpenSubtitles when configured).
    /// The first preferred-language result can be downloaded and enabled automatically.
    func refreshSubtitlesFromProviders(autoSelectPreferred: Bool = false) async {
        guard !isLoadingSubtitles else { return }
        guard let contentID = item.contentID, let catalog else {
            subtitleStatusMessage = subtitleTracks.isEmpty
                ? "This item has no catalog ID for subtitle lookup."
                : nil
            if autoSelectPreferred { await autoEnablePreferredSubtitle() }
            return
        }

        isLoadingSubtitles = true
        subtitleStatusMessage = "Searching subtitle add-ons…"
        let fetched = await catalog.subtitles(for: contentID, episode: item.episode)
        mergeSubtitleTracks(fetched)
        isLoadingSubtitles = false

        if fetched.isEmpty {
            subtitleStatusMessage = subtitleTracks.isEmpty
                ? "No subtitle add-on returned a match."
                : "No new subtitles found."
        } else {
            subtitleStatusMessage = "Found \(fetched.count) subtitle option\(fetched.count == 1 ? "" : "s")."
        }

        if autoSelectPreferred, !didAttemptAutomaticSubtitles {
            didAttemptAutomaticSubtitles = true
            await autoEnablePreferredSubtitle()
        }
    }

    private func mergeSubtitleTracks(_ tracks: [SubtitleTrack]) {
        var seen = Set<String>()
        let merged = subtitleTracks + tracks
        subtitleTracks = merged.filter { track in
            let key = "\(track.language.lowercased())|\(track.url?.absoluteString ?? track.id)"
            return seen.insert(key).inserted
        }
        item.subtitles = subtitleTracks
    }

    func selectSubtitle(_ track: SubtitleTrack?) {
        selectedSubtitleID = track?.id
        showSubtitlePicker = false

        guard let track else {
            externalSubtitleCues = []
            activeSubtitleText = nil
            disableEmbeddedSubtitles()
            subtitleStatusMessage = "Subtitles are off."
            return
        }

        if track.isEmbedded {
            externalSubtitleCues = []
            activeSubtitleText = nil
            selectEmbeddedLegibleOption(matching: track)
            subtitleStatusMessage = "Using embedded \(track.languageDisplay) subtitles."
            return
        }

        // External SRT/VTT files are rendered as timed text above the native player
        // controls. This works for direct files and HLS without relying on AVPlayer to
        // accept a sideloaded text track inside a mutable composition.
        disableEmbeddedSubtitles()
        subtitleStatusMessage = "Downloading \(track.languageDisplay) subtitles…"
        Task { [weak self] in
            guard let self else { return }
            guard let local = await self.ensureLocalSubtitle(track) else {
                self.subtitleStatusMessage = "The selected subtitle could not be downloaded."
                return
            }
            self.activateExternalSubtitle(localURL: local, track: track)
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
            let (data, _) = try await AppNetworking.shared.data(from: sourceURL)
            let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) ?? ""
            let vtt = SubtitleConverter.srtToVTT(text)

            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("subtitles", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let safeID = track.id
                .replacingOccurrences(of: ":", with: "_")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "\\", with: "_")
            let fileURL = dir.appendingPathComponent("\(safeID).vtt")
            try vtt.data(using: .utf8)?.write(to: fileURL, options: [.atomic])
            localSubtitleFiles[track.id] = fileURL
            return fileURL
        } catch {
            return nil
        }
    }

    /// Parses and activates a downloaded subtitle file. `ensureLocalSubtitle` stores
    /// a normalized WebVTT file, but the parser also accepts SRT timestamps so local
    /// provider variations do not break playback.
    private func activateExternalSubtitle(localURL: URL, track: SubtitleTrack) {
        do {
            let raw = try String(contentsOf: localURL, encoding: .utf8)
            let cues = Self.parseSubtitleCues(raw)
            guard !cues.isEmpty else {
                subtitleStatusMessage = "The subtitle file did not contain readable cues."
                return
            }
            externalSubtitleCues = cues
            updateExternalSubtitle(at: currentTime)
            subtitleStatusMessage = "Using \(track.languageDisplay) subtitles from \(track.source)."
        } catch {
            subtitleStatusMessage = "The selected subtitle could not be opened."
        }
    }

    private func updateExternalSubtitle(at time: TimeInterval) {
        guard !externalSubtitleCues.isEmpty else {
            if activeSubtitleText != nil { activeSubtitleText = nil }
            return
        }

        var low = 0
        var high = externalSubtitleCues.count - 1
        var candidate: SubtitleCue?
        while low <= high {
            let mid = (low + high) / 2
            let cue = externalSubtitleCues[mid]
            if cue.start <= time {
                candidate = cue
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        let nextText: String?
        if let candidate, time <= candidate.end {
            nextText = candidate.text
        } else {
            nextText = nil
        }
        if activeSubtitleText != nextText { activeSubtitleText = nextText }
    }

    private static func parseSubtitleCues(_ input: String) -> [SubtitleCue] {
        let normalized = input
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")
        var cues: [SubtitleCue] = []

        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
            guard !lines.isEmpty else { continue }
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let timing = lines[timingIndex].components(separatedBy: "-->")
            guard timing.count == 2,
                  let start = parseSubtitleTimestamp(timing[0]),
                  let end = parseSubtitleTimestamp(timing[1]) else { continue }

            let text = lines.dropFirst(timingIndex + 1)
                .joined(separator: "\n")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, end >= start else { continue }
            cues.append(SubtitleCue(start: start, end: end, text: text))
        }
        return cues.sorted { $0.start < $1.start }
    }

    private static func parseSubtitleTimestamp(_ raw: String) -> TimeInterval? {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ").first.map(String.init) ?? ""
        let normalized = token.replacingOccurrences(of: ",", with: ".")
        let parts = normalized.split(separator: ":").map(String.init)
        guard parts.count == 2 || parts.count == 3 else { return nil }

        let secondsPart = parts.last ?? ""
        guard let seconds = Double(secondsPart),
              let minutes = Double(parts[parts.count - 2]) else { return nil }
        let hours = parts.count == 3 ? (Double(parts[0]) ?? 0) : 0
        return hours * 3600 + minutes * 60 + seconds
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

    private func disableEmbeddedSubtitles() {
        guard let playerItem = player.currentItem else { return }
        Task {
            guard let group = try? await playerItem.asset.loadMediaSelectionGroup(for: .legible) else { return }
            playerItem.select(nil, in: group)
        }
    }

    private func autoEnablePreferredSubtitle() async {
        guard let preferred = settings?.subtitleLanguage else { return }
        if let match = subtitleTracks.first(where: {
            $0.matchesPreferredLanguage(preferred)
        }) {
            await MainActor.run { self.selectSubtitle(match) }
        }
    }

    // MARK: - Transport

    func retry() {
        teardownObservers()
        start()
    }

    func play() { player.play() }

    /// Applies the user's default playback speed to the AVPlayer. Called after play
    /// begins; setting rate directly also resumes playback at that speed.
    func applyPlaybackSpeed() {
        guard let speed = settings?.playbackSpeed, speed > 0 else { return }
        // defaultRate keeps the speed across play/pause; rate applies it now.
        player.defaultRate = Float(speed)
        if player.timeControlStatus == .playing || player.rate != 0 {
            player.rate = Float(speed)
        }
    }
    func pause() {
        checkpointProgress()
        player.pause()
        scrobble(.pause)
    }

    func stopAndSave() {
        PlaybackCoordinator.shared.resign(self)
        saveTask?.cancel(); saveTask = nil
        checkpointProgress()
        scrobble(.stop)
        player.pause()
        NowPlayingStore.shared.clear()
        teardownObservers()
    }

    /// The user left the player screen without explicitly stopping. Save position and
    /// pause the pipeline, but keep the Now Playing / Resume bar alive (minimize) so
    /// they can jump back in. Tapping the bar reopens the player and resumes.
    func minimizeAndSave() {
        PlaybackCoordinator.shared.resign(self)
        saveTask?.cancel(); saveTask = nil
        checkpointProgress()
        scrobble(.pause)
        player.pause()
        NowPlayingStore.shared.minimize()
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
