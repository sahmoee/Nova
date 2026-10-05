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
    /// Read back from VLC, never optimistic copies of the tapped row.
    @Published private(set) var selectedSubtitleTrackID: Int?
    @Published private(set) var selectedAudioTrackID: Int?
    @Published private(set) var pendingExternalSubtitleID: String?
    @Published private(set) var isDownloadingSubtitle = false
    @Published private(set) var isLoadingExternalSubtitles = false
    @Published private(set) var subtitleStatusMessage: String?
    @Published var showSubtitlePicker = false
    /// The engine's current rate, for the overlay's speed badge.
    @Published private(set) var playbackRate: Double = 1

    struct VLCTrack: Identifiable, Hashable {
        let id: Int          // VLC track index
        let name: String
    }

    let item: MediaItem

    private var progressStore: PlaybackProgressStore?
    private var settings: SettingsStore?
    private var trackers: TrackingHub?
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
    private var subtitleSelection = SubtitleSelectionGate()
    private var subtitleDownloadTask: Task<Void, Never>?
    private var subtitleRegistrationTask: Task<Int?, Never>?
    private var registrationRevision = UUID()
    private var attachedSubtitleIDs: [URL: Int] = [:]
    private var externalSubtitleIDsByTrackIndex: [Int: String] = [:]
    private var unresolvedAttachment: (url: URL, previousIDs: Set<Int>)?
    private var lastNowPlayingUptime: TimeInterval = 0
    private var stallTask: Task<Void, Never>?
    private var didApplyAudioPreference = false
    private static let preferredAudioKey = "player.vlc.preferredAudioTrackName"
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
                   trackers: TrackingHub,
                   catalog: CatalogService,
                   openSubtitles: OpenSubtitlesClient,
                   libraryStore: LibraryStore? = nil) {
        self.progressStore = progressStore
        self.settings = settings
        self.trackers = trackers
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
        subtitleSelection.cancel(); subtitleDownloadTask?.cancel(); subtitleDownloadTask = nil
        registrationRevision = UUID(); subtitleRegistrationTask?.cancel(); subtitleRegistrationTask = nil
        attachedSubtitleIDs = [:]; externalSubtitleIDsByTrackIndex = [:]; unresolvedAttachment = nil
        selectedSubtitleTrackID = nil; selectedAudioTrackID = nil; selectedExternalSubtitleID = nil
        pendingExternalSubtitleID = nil; isDownloadingSubtitle = false
        didApplyAudioPreference = false
        stallTask?.cancel(); stallTask = nil

        let media = VLCMedia(url: item.playbackURL)
        // libVLC media options are ":name=value". The earlier "--name" spelling was
        // silently ignored, so profile caching never applied. Caching now adapts to
        // the source: short for local files and the SMB bridge, longer for remote
        // and constrained networks, with HTTP reconnect for remote streams.
        let options = VLCStreamingPolicy.mediaOptions(
            for: item.playbackURL,
            isLive: item.sourceType == .liveTV,
            profileCacheMilliseconds: settings?.builtInPlayer.vlcNetworkCacheMs,
            prefersHardwareDecoding: settings?.builtInPlayer.prefersHardwareDecoding ?? false,
            constrained: NetworkConditionMonitor.shared.shouldSuggestBandwidthSaver
        )
        for option in options { media.addOption(option) }
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
        cancelPendingSubtitleSelection()
        // Idempotent: the back button and onDisappear can both call this.
        guard isActive else { return }
        isActive = false
        stallTask?.cancel(); stallTask = nil
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
        cancelPendingSubtitleSelection()
        guard isActive else { return }
        isActive = false
        stallTask?.cancel(); stallTask = nil
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

    func pauseAndSave() {
        #if canImport(VLCKitSPM)
        guard isActive, mediaPlayer.isPlaying else { return }
        checkpointProgress()
        mediaPlayer.pause()
        scrobble(.pause)
        #endif
    }

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

    /// Skips relative to the displayed time, so repeated taps accumulate (three taps
    /// move 30 seconds) and the timeline updates immediately instead of waiting for
    /// VLC's next time callback.
    func skipForward(_ secs: Int = 15) {
        seek(to: currentTime + TimeInterval(secs))
    }

    func skipBackward(_ secs: Int = 15) {
        seek(to: currentTime - TimeInterval(secs))
    }

    var remainingTime: TimeInterval { max(duration - currentTime, 0) }

    // MARK: - Subtitle / audio tracks

    func selectSubtitleTrack(_ track: VLCTrack?) {
        cancelPendingSubtitleSelection()
        #if canImport(VLCKitSPM)
        mediaPlayer.currentVideoSubTitleIndex = Int32(track?.id ?? -1)
        refreshTracks()
        subtitleStatusMessage = nil
        showSubtitlePicker = false
        #endif
    }

    func disableSubtitles() {
        cancelPendingSubtitleSelection()
        #if canImport(VLCKitSPM)
        mediaPlayer.currentVideoSubTitleIndex = -1
        refreshTracks()
        subtitleStatusMessage = selectedSubtitleTrackID == -1 ? "Subtitles are off." : "Disabling subtitles…"
        showSubtitlePicker = false
        #endif
    }

    func selectAudioTrack(_ track: VLCTrack) {
        #if canImport(VLCKitSPM)
        mediaPlayer.currentAudioTrackIndex = Int32(track.id)
        refreshTracks()
        // Remember the choice so the next title starts on the same language.
        UserDefaults.standard.set(track.name, forKey: Self.preferredAudioKey)
        #endif
    }

    /// Applies the remembered audio language once per session when a matching track
    /// exists. Matching is by the track's language label, never by index.
    private func applyPreferredAudioTrackIfNeeded() {
        #if canImport(VLCKitSPM)
        guard !didApplyAudioPreference, audioTracks.count > 1 else { return }
        didApplyAudioPreference = true
        guard let saved = UserDefaults.standard.string(forKey: Self.preferredAudioKey),
              let match = VLCStreamingPolicy.preferredAudioTrack(named: saved, in: audioTracks.map { (id: $0.id, name: $0.name) }),
              match != selectedAudioTrackID else { return }
        mediaPlayer.currentAudioTrackIndex = Int32(match)
        refreshTracks()
        #endif
    }

    /// A later Off, embedded choice, sheet dismissal, or stop wins over pending work.
    func cancelPendingSubtitleSelection() {
        let wasPending = isDownloadingSubtitle
        subtitleSelection.cancel(); subtitleDownloadTask?.cancel(); subtitleDownloadTask = nil
        pendingExternalSubtitleID = nil; isDownloadingSubtitle = false
        didAttemptAutomaticSubtitles = true
        if wasPending { subtitleStatusMessage = "Subtitle download cancelled." }
    }

    var subtitlesAreOff: Bool { selectedSubtitleTrackID == -1 }
    var playerSubtitleTracks: [VLCTrack] { subtitleTracks.filter { externalSubtitleIDsByTrackIndex[$0.id] == nil } }

    /// Finite, bounded persisted values keep the preview and native renderer safe.
    @Published var subtitleScale: Double = SubtitleScalePolicy.normalized(UserDefaults.standard.object(forKey: "player.subtitleScale") as? Double ?? 1) {
        didSet {
            let normalized = SubtitleScalePolicy.normalized(subtitleScale)
            if subtitleScale != normalized { subtitleScale = normalized }
            UserDefaults.standard.set(normalized, forKey: "player.subtitleScale")
            applySubtitleScale()
        }
    }

    func applySubtitleScale() {
        #if canImport(VLCKitSPM)
        // VLCMediaPlayer.setTextRendererFontSize is not exposed on all builds, so we
        // guard the call. Larger scale => bigger text; VLC font size is in points.
        // Map scale 0.5...2.5 onto roughly 12...60pt.
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

    /// Copy a picked file while its security-scoped access is still active. VLC may
    /// read it after the importer callback returns, so it must own a stable local URL.
    func addExternalSubtitle(_ url: URL) {
        cancelPendingSubtitleSelection()
        do {
            let dir = try subtitleDirectory()
            let local = dir.appendingPathComponent(UUID().uuidString).appendingPathExtension(url.pathExtension.isEmpty ? "srt" : url.pathExtension)
            try FileManager.default.copyItem(at: url, to: local)
            let request = subtitleSelection.begin(local.lastPathComponent)
            isDownloadingSubtitle = true
            subtitleStatusMessage = "Opening subtitle file…"
            subtitleDownloadTask = Task { [weak self] in
                guard let self else { return }
                defer { self.finishSubtitleRequest(request) }
                do {
                    try await self.attachSubtitle(local, externalID: nil, request: request)
                    guard self.subtitleSelection.accepts(request), !Task.isCancelled else { return }
                    self.subtitleStatusMessage = "Using the imported subtitle file."
                    self.showSubtitlePicker = false
                } catch is CancellationError { }
                catch {
                    guard self.subtitleSelection.accepts(request) else { return }
                    self.subtitleStatusMessage = error.localizedDescription
                }
            }
        } catch { subtitleStatusMessage = "The subtitle file could not be opened: \(error.localizedDescription)" }
    }

    /// Searches enabled subtitle add-ons and exposes their results in the picker.
    /// When requested at startup, the preferred language is downloaded and selected.
    func refreshExternalSubtitles(autoSelectPreferred: Bool = false) async {
        guard !isLoadingExternalSubtitles else { return }
        let selectionRevision = subtitleSelection.revision
        guard let contentID = item.contentID, let catalog else {
            subtitleStatusMessage = externalSubtitleTracks.isEmpty
                ? "This item has no catalog ID for subtitle lookup."
                : nil
            if autoSelectPreferred, !didAttemptAutomaticSubtitles { await autoSelectPreferredExternalSubtitle() }
            return
        }

        isLoadingExternalSubtitles = true
        subtitleStatusMessage = "Searching subtitle add-ons…"
        let fetched = await catalog.subtitles(for: contentID, episode: item.episode)
        isLoadingExternalSubtitles = false
        guard !Task.isCancelled, isActive else { return }
        mergeExternalSubtitleTracks(fetched)
        if selectionRevision == subtitleSelection.revision, !isDownloadingSubtitle {
            subtitleStatusMessage = fetched.isEmpty
                ? (externalSubtitleTracks.isEmpty ? "No subtitle add-on returned a match." : "No new subtitles found.")
                : "Found \(fetched.count) subtitle option\(fetched.count == 1 ? "" : "s")."
        }
        if autoSelectPreferred, !didAttemptAutomaticSubtitles, selectionRevision == subtitleSelection.revision {
            await autoSelectPreferredExternalSubtitle()
        }
    }

    func selectExternalSubtitle(_ track: SubtitleTrack) {
        cancelPendingSubtitleSelection()
        let request = subtitleSelection.begin(track.id)
        pendingExternalSubtitleID = track.id; isDownloadingSubtitle = true
        subtitleDownloadTask = Task { [weak self] in
            guard let self else { return }
            await self.downloadAndAttachSubtitle(track, request: request)
        }
    }

    private func mergeExternalSubtitleTracks(_ tracks: [SubtitleTrack]) {
        var seen = Set<String>()
        externalSubtitleTracks = (externalSubtitleTracks + tracks).filter { track in
            let key = "\(track.language.lowercased())|\(track.url?.absoluteString ?? track.id)"
            return seen.insert(key).inserted
        }
    }

    private func autoSelectPreferredExternalSubtitle() async {
        guard !didAttemptAutomaticSubtitles, isActive,
              settings?.subtitlesEnabled == true,
              let preferred = settings?.subtitleLanguage,
              let match = externalSubtitleTracks.first(where: { $0.matchesPreferredLanguage(preferred) }) else { return }
        didAttemptAutomaticSubtitles = true
        selectExternalSubtitle(match)
        await subtitleDownloadTask?.value
    }

    private func finishSubtitleRequest(_ request: UUID) {
        guard subtitleSelection.finish(request) else { return }
        pendingExternalSubtitleID = nil; isDownloadingSubtitle = false; subtitleDownloadTask = nil
    }

    private func subtitleDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vlc_subtitles", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func downloadAndAttachSubtitle(_ track: SubtitleTrack, request: UUID) async {
        defer { finishSubtitleRequest(request) }
        do {
            var local = localSubtitleFiles[track.id]
            if local == nil {
                subtitleStatusMessage = "Downloading \(track.languageDisplay) subtitles…"
                var sourceURL = track.url
                if sourceURL == nil, track.id.hasPrefix("os:"), let fileID = Int(track.id.dropFirst(3)) {
                    sourceURL = try await openSubtitles?.requestDownload(fileID: fileID)
                }
                try Task.checkCancellation()
                guard subtitleSelection.accepts(request) else { throw CancellationError() }
                guard let sourceURL else { throw SubtitleAttachmentError.message("The selected subtitle could not be downloaded.") }
                let (data, response) = try await AppNetworking.shared.data(from: sourceURL)
                try Task.checkCancellation()
                guard subtitleSelection.accepts(request) else { throw CancellationError() }
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw SubtitleAttachmentError.message("The subtitle provider returned HTTP \(http.statusCode). Choose another track or retry.")
                }
                guard !data.isEmpty else { throw SubtitleAttachmentError.message("The subtitle provider returned an empty file.") }
                let name = response.suggestedFilename ?? sourceURL.lastPathComponent
                let ext = URL(fileURLWithPath: name).pathExtension
                let destination = try subtitleDirectory().appendingPathComponent(UUID().uuidString).appendingPathExtension(ext.isEmpty ? "srt" : ext)
                try data.write(to: destination, options: [.atomic])
                localSubtitleFiles[track.id] = destination; local = destination
            }
            guard let local else { return }
            try await attachSubtitle(local, externalID: track.id, request: request)
            guard subtitleSelection.accepts(request), !Task.isCancelled else { return }
            subtitleStatusMessage = "Using \(track.languageDisplay) subtitles from \(track.source)."
            showSubtitlePicker = false
        } catch is CancellationError { }
        catch {
            guard subtitleSelection.accepts(request), !Task.isCancelled else { return }
            subtitleStatusMessage = error.localizedDescription
        }
    }

    /// Register without native auto-selection. Manual Off therefore cannot be undone
    /// by VLC registering a previously requested file after the download was cancelled.
    private func attachSubtitle(_ url: URL, externalID: String?, request: UUID) async throws {
        #if canImport(VLCKitSPM)
        if let pending = subtitleRegistrationTask { _ = await pending.value }
        try Task.checkCancellation()
        guard subtitleSelection.accepts(request), isActive else { throw CancellationError() }
        refreshTracks()
        var index = attachedSubtitleIDs[url]
        if index == nil {
            guard unresolvedAttachment == nil else {
                throw SubtitleAttachmentError.message("VLC is still registering a subtitle. Check Player tracks before adding another file.")
            }
            let before = Set(subtitleTracks.map(\.id))
            guard mediaPlayer.addPlaybackSlave(url, type: .subtitle, enforce: false) == 0 else {
                throw SubtitleAttachmentError.message("VLC could not open this subtitle file. Your active track is unchanged.")
            }
            unresolvedAttachment = (url, before)
            let revision = UUID(); registrationRevision = revision
            // Registration bookkeeping continues after a cancelled choice. The next
            // request waits for it, so two added files cannot exchange their track IDs.
            let task = Task<Int?, Never> { [weak self] in
                for _ in 0..<30 {
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { return nil }
                    guard let self, self.isActive, self.registrationRevision == revision else { return nil }
                    self.refreshTracks()
                    if let index = self.attachedSubtitleIDs[url] { return index }
                }
                return nil
            }
            subtitleRegistrationTask = task
            index = await task.value
            if registrationRevision == revision { subtitleRegistrationTask = nil }
        }
        try Task.checkCancellation()
        guard subtitleSelection.accepts(request), isActive else { throw CancellationError() }
        guard let index else {
            throw SubtitleAttachmentError.message("VLC has not exposed the added subtitle yet. Check Player tracks; the previous selection is unchanged.")
        }
        mediaPlayer.currentVideoSubTitleIndex = Int32(index)
        // Apply only while current, then confirm the engine's actual index.
        for _ in 0..<10 {
            refreshTracks()
            if selectedSubtitleTrackID == index {
                if let externalID { externalSubtitleIDsByTrackIndex[index] = externalID }
                refreshTracks()
                return
            }
            try await Task.sleep(for: .milliseconds(100))
            guard subtitleSelection.accepts(request), isActive else { throw CancellationError() }
        }
        throw SubtitleAttachmentError.message("VLC did not confirm that subtitle selection. Check the active track before retrying.")
        #else
        throw SubtitleAttachmentError.message("VLC playback engine is unavailable in this build.")
        #endif
    }

    private enum SubtitleAttachmentError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let value) = self { value } else { nil } }
    }

    /// Whether the video fills the screen (cropping) vs. fits with letterboxing.
    /// The actual fill is applied at the SwiftUI view layer (a scale on the player
    /// surface), which works on any VLCKit build and can't crash — unlike VLCKit's
    /// videoCropGeometry, which isn't key-value-coding compliant on this build.
    @Published var fillScreen: Bool = UserDefaults.standard.bool(forKey: "player.vlc.fillScreen") {
        didSet { UserDefaults.standard.set(fillScreen, forKey: "player.vlc.fillScreen") }
    }

    // MARK: - Progress

    private func startSaveLoop() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run { self?.checkpointProgress(periodic: true) }
            }
        }
    }

    func checkpointProgress(periodic: Bool = false) {
        guard item.sourceType != .liveTV, duration > 0, currentTime > 0 else { return }
        progressStore?.save(position: currentTime, duration: duration, for: item, periodic: periodic)
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
            playbackRate = speed
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
        let clamped = max(0.25, min(rate, 3.0))
        mediaPlayer.rate = Float(clamped)
        playbackRate = clamped
        #endif
    }

    /// Restarts the current title from the beginning without leaving the player.
    func restartFromBeginning() {
        progressStore?.reset(for: item)
        seek(to: 0)
    }

    // MARK: - Watch tracking

    private func scrobble(_ action: ScrobbleAction) {
        guard let trackers, let contentID = item.contentID else { return }
        if action == .start { hasScrobbledStart = true }
        let pct = progressPercent
        let ep = item.episode
        Task.detached {
            await trackers.scrobble(action: action, contentID: contentID, episode: ep, progress: pct)
        }
    }

    private func scrobbleProgressIfNeeded() {
        let pct = progressPercent
        if abs(pct - lastScrobbleProgress) >= 5 {
            lastScrobbleProgress = pct
            scrobble(.pause)
        }
    }

    func refreshTracks() {
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
        let subtitles = tracks(indices: mediaPlayer.videoSubTitlesIndexes, names: mediaPlayer.videoSubTitlesNames)
        let audio = tracks(indices: mediaPlayer.audioTrackIndexes, names: mediaPlayer.audioTrackNames)
        let subtitleIndex = Int(mediaPlayer.currentVideoSubTitleIndex)
        let audioIndex = Int(mediaPlayer.currentAudioTrackIndex)
        // Registration polls the engine briefly; identical samples must not rebuild
        // the entire player and picker every 100 ms.
        if subtitleTracks != subtitles { subtitleTracks = subtitles }
        if audioTracks != audio { audioTracks = audio }
        if selectedSubtitleTrackID != subtitleIndex { selectedSubtitleTrackID = subtitleIndex }
        if selectedAudioTrackID != audioIndex { selectedAudioTrackID = audioIndex }
        if let pending = unresolvedAttachment {
            let added = subtitleTracks.filter { !pending.previousIDs.contains($0.id) }
            if added.count == 1 {
                attachedSubtitleIDs[pending.url] = added[0].id
                unresolvedAttachment = nil
            }
        }
        let externalID = externalSubtitleIDsByTrackIndex[subtitleIndex]
        if selectedExternalSubtitleID != externalID { selectedExternalSubtitleID = externalID }
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
                if !mediaPlayer.isPlaying {
                    self.isBuffering = true
                    self.armStallWatchdog()
                }
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
                self.applyPreferredAudioTrackIfNeeded()
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
            let reported = TimeInterval(ms) / 1000.0
            // VLC reports time many times a second. Publishing each sample re-rendered
            // the whole overlay; quarter-second steps look identical and cost far less.
            if VLCStreamingPolicy.shouldPublishTime(reported, previous: self.currentTime) {
                self.currentTime = reported
            }
            // Time is advancing, so we're playing, not buffering. This is the reliable
            // signal to clear a spinner that VLC's buffering state left stuck on.
            if self.isBuffering { self.isBuffering = false }
            self.stallTask?.cancel(); self.stallTask = nil
            if self.state == .loading {
                self.state = .ready
                self.markReady()
            }
            // VLC length becomes known shortly after play starts.
            let lengthMs = mediaPlayer.media?.length.intValue ?? 0
            if lengthMs > 0 {
                let length = TimeInterval(lengthMs) / 1000.0
                if length != self.duration { self.duration = length }
            }
            self.scrobbleProgressIfNeeded()
            // Feed the Now Playing mini-bar about once a second.
            let uptime = ProcessInfo.processInfo.systemUptime
            if uptime - self.lastNowPlayingUptime >= 1 {
                self.lastNowPlayingUptime = uptime
                let frac = self.duration > 0 ? self.currentTime / self.duration : 0
                NowPlayingStore.shared.update(progress: frac, isPlaying: self.isPlaying)
            }
        }
    }

    /// A stall that outlives a normal rebuffer is nudged by re-seeking to the current
    /// time, which makes VLC reopen the network read at that offset.
    @MainActor
    private func armStallWatchdog() {
        guard stallTask == nil, isActive else { return }
        stallTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, !Task.isCancelled, self.isActive, self.isBuffering else { return }
            self.stallTask = nil
            self.seek(to: self.currentTime)
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

// MARK: - Streaming policy

/// Pure libVLC option and publication decisions, kept separate so they can be
/// checked without the VLC engine.
enum VLCStreamingPolicy {
    /// Read-ahead in milliseconds. A profile override (Slow Connection, Hardware,
    /// Compatibility) wins; otherwise local sources stay responsive and remote or
    /// constrained networks buffer more.
    static func cacheMilliseconds(for url: URL, isLive: Bool, profileOverride: Int?, constrained: Bool) -> Int {
        if let profileOverride, profileOverride > 0 { return min(profileOverride, 20_000) }
        if url.isFileURL { return 300 }
        if AVStreamingPolicy.isLocal(url) { return 800 }
        var milliseconds = isLive ? 1_500 : 2_500
        if constrained { milliseconds += 1_500 }
        return milliseconds
    }

    static func mediaOptions(for url: URL, isLive: Bool, profileCacheMilliseconds: Int?,
                             prefersHardwareDecoding: Bool, constrained: Bool) -> [String] {
        let cache = cacheMilliseconds(for: url, isLive: isLive, profileOverride: profileCacheMilliseconds, constrained: constrained)
        var options = [":network-caching=\(cache)", ":file-caching=\(min(cache, 1_500))"]
        if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", !AVStreamingPolicy.isLocal(url) {
            options.append(":http-reconnect")
        }
        if prefersHardwareDecoding { options.append(":codec=videotoolbox,any") }
        return options
    }

    /// Publish a new time when it moved a quarter second or more, or went backward
    /// (a seek or restart), or when playback reached zero.
    static func shouldPublishTime(_ reported: TimeInterval, previous: TimeInterval) -> Bool {
        guard reported.isFinite, reported >= 0 else { return false }
        return reported < previous || reported - previous >= 0.25 || (reported == 0 && previous != 0)
    }

    /// Finds the track whose label matches a remembered label, first exactly, then by
    /// its leading language word ("English - 5.1" matches "English").
    static func preferredAudioTrack(named saved: String, in tracks: [(id: Int, name: String)]) -> Int? {
        let target = saved.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !target.isEmpty else { return nil }
        if let exact = tracks.first(where: { $0.name.lowercased() == target }) { return exact.id }
        func language(_ name: String) -> String {
            let cleaned = name.lowercased().replacingOccurrences(of: "track", with: "")
            return cleaned.split(whereSeparator: { !$0.isLetter }).first.map(String.init) ?? ""
        }
        let wanted = language(target)
        guard wanted.count >= 2 else { return nil }
        return tracks.first(where: { language($0.name) == wanted })?.id
    }
}
