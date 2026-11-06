//
//  PlaybackProgressStore.swift
//  Nova
//
//  Saves and restores playback positions. Progress is resolved by the stable content
//  identity as well as UUID, because stream resolution can create a fresh MediaItem
//  instance while the library intentionally keeps the original persisted UUID.
//

import Foundation
#if DEBUG
import CloudKit
#endif

@MainActor
final class PlaybackProgressStore: ObservableObject {

    private unowned let library: LibraryStore
    #if DEBUG
    private var cloudPlayback: CloudPlaybackSync?
    private var openingCloudPlayback = false
    private var libraryRecordSnapshot: [String: CloudLibraryRecord] = [:]
    private var cloudLibraryApplyTask: Task<Void, Never>?
    #endif
    /// Uptime of the last library write per title, used to coalesce the players'
    /// five-second safety checkpoints.
    private var lastWriteUptime: [String: TimeInterval] = [:]
    /// Periodic checkpoints reach disk at most this often. Pause, stop, minimize,
    /// background and completion always write immediately.
    static let periodicWriteInterval: TimeInterval = 30

    init(library: LibraryStore) {
        self.library = library
    }

    #if DEBUG
    /// Launch with -NovaCloudPlaybackPilot YES to exercise the development container.
    func refreshCloudPlayback() async {
        guard UserDefaults.standard.bool(forKey: "NovaCloudPlaybackPilot"),
              !openingCloudPlayback,
              !CloudSync.shared.isPaused(.history),
              !CloudSync.shared.isPaused(.library) else { return }
        openingCloudPlayback = true
        defer { openingCloudPlayback = false }
        if let cloudPlayback {
            if await cloudPlayback.refresh(importLegacy: legacyPlaybackCheckpoints) {
                activateRecordSync(cloudPlayback)
            }
            return
        }
        let container = CKContainer(identifier: "iCloud.com.nova.ios")
        do {
            let account = try await container.userRecordID()
            let accountKey = CloudPlaybackSync.recordName(for: account.recordName)
            let support = try FileManager.default.url(for: .applicationSupportDirectory,
                                                      in: .userDomainMask, appropriateFor: nil, create: true)
            let sync = try CloudPlaybackSync(
                database: container.privateCloudDatabase, account: account,
                file: support.appendingPathComponent("nova-playback-\(accountKey).json"),
                apply: { [weak self] name, checkpoint in
                    self?.applyCloudPlayback(checkpoint, for: name)
                },
                report: { [weak self] message in
                    NovaLog.sync.error("CloudKit playback: \(message)")
                    if self?.cloudPlayback?.isConnected == false {
                        self?.library.usesRecordPlayback = false
                        self?.library.usesRecordLibrary = false
                    }
                }
            )
            cloudPlayback = sync
            library.playbackDidPersist = { [weak self] item in self?.queueCloudPlayback(item) }
            library.libraryDidReceiveCloud = { [weak self] in self?.cloudPlayback?.replay() }
            library.libraryRecordsDidPersist = { [weak self] in _ = self?.queueCloudLibraryChanges() }
            if await sync.refresh(importLegacy: legacyPlaybackCheckpoints) {
                activateRecordSync(sync)
            }
        } catch {
            NovaLog.sync.error("CloudKit playback: \(error.localizedDescription)")
        }
    }

    private func legacyPlaybackCheckpoints() -> [String: CloudPlaybackSync.Checkpoint] {
        let cloud = CloudSync.shared
        guard !cloud.isPaused(.history), !cloud.isPaused(.library) else { return [:] }
        let deletedAt = max(cloud.deletionDate(.history), cloud.deletionDate(.library))
        var checkpoints: [String: CloudPlaybackSync.Checkpoint] = [:]
        for item in library.items where item.sourceType != .liveTV {
            guard let played = item.lastPlayedDate, played.timeIntervalSince1970 > deletedAt,
                  item.lastPlayedPosition.isFinite, item.lastPlayedPosition >= 0 else { continue }
            let name = CloudPlaybackSync.recordName(for: item.contentKey)
            if let existing = checkpoints[name], existing.revision >= played { continue }
            let checkpoint = CloudPlaybackSync.Checkpoint(
                position: item.lastPlayedPosition, duration: MediaReliabilityPolicy.validDuration(item.duration),
                lastPlayed: played, revision: played, operation: item.id)
            checkpoints[name] = checkpoint
            addHistoryEvent(for: item, name: name, checkpoint: checkpoint, into: &checkpoints)
        }
        if !library.usesRecordLibrary {
            libraryRecordSnapshot = recordSnapshot()
            for (name, record) in libraryRecordSnapshot {
                checkpoints[name] = libraryCheckpoint(record, revision: Date())
            }
        }
        return checkpoints
    }

    private func activateRecordSync(_ sync: CloudPlaybackSync) {
        library.usesRecordPlayback = true
        library.usesRecordLibrary = true
        applyCloudLibrary(sync)
    }

    private func recordSnapshot() -> [String: CloudLibraryRecord] {
        Dictionary(library.cloudLibraryRecords().map {
            (CloudPlaybackSync.recordName(for: $0.identity), $0)
        }, uniquingKeysWith: { first, _ in first })
    }

    private func libraryCheckpoint(_ record: CloudLibraryRecord, revision: Date) -> CloudPlaybackSync.Checkpoint {
        CloudPlaybackSync.Checkpoint(position: 0, duration: nil, lastPlayed: nil,
                                     revision: revision, operation: UUID(), libraryRecord: record)
    }

    @discardableResult
    private func queueCloudLibraryChanges() -> Bool {
        guard library.usesRecordLibrary, !CloudSync.shared.isPaused(.library), let cloudPlayback else { return false }
        let snapshot = recordSnapshot()
        let now = Date()
        var changes: [String: CloudPlaybackSync.Checkpoint] = [:]
        for (name, record) in snapshot where libraryRecordSnapshot[name] != record {
            changes[name] = libraryCheckpoint(record, revision: now)
        }
        for (name, record) in libraryRecordSnapshot where snapshot[name] == nil {
            changes[name] = libraryCheckpoint(record.tombstone, revision: now)
        }
        guard cloudPlayback.enqueue(changes) else { return false }
        libraryRecordSnapshot = snapshot
        return true
    }

    private func applyCloudLibrary(_ sync: CloudPlaybackSync) {
        guard sync.isConnected, queueCloudLibraryChanges() else { return }
        let deletedAt = CloudSync.shared.deletionDate(.library)
        library.applyCloudLibraryRecords(sync.libraryRecords(after: deletedAt))
        libraryRecordSnapshot = recordSnapshot()
        sync.replay()
    }

    private func applyCloudPlayback(_ checkpoint: CloudPlaybackSync.Checkpoint, for name: String) {
        if checkpoint.libraryRecord != nil {
            guard library.usesRecordLibrary else { return }
            cloudLibraryApplyTask?.cancel()
            cloudLibraryApplyTask = Task { [weak self] in
                guard !Task.isCancelled, let self, let sync = cloudPlayback else { return }
                applyCloudLibrary(sync)
            }
            return
        }
        guard checkpoint.historyTitle == nil,
              !CloudSync.shared.isPaused(.history), !CloudSync.shared.isPaused(.library),
              checkpoint.revision.timeIntervalSince1970 > CloudSync.shared.deletionDate(.history),
              checkpoint.revision.timeIntervalSince1970 > CloudSync.shared.deletionDate(.library),
              var item = library.items.first(where: { CloudPlaybackSync.recordName(for: $0.contentKey) == name })
        else { return }
        guard item.lastPlayedDate.map({ $0 <= checkpoint.revision }) ?? true else { return }
        item.lastPlayedPosition = checkpoint.position
        item.lastPlayedDate = checkpoint.lastPlayed
        if let duration = MediaReliabilityPolicy.validDuration(checkpoint.duration) {
            item.duration = duration
        }
        library.updateProgress(item, immediate: true, publishToCloud: false)
    }

    private func queueCloudPlayback(_ item: MediaItem) {
        guard !CloudSync.shared.isPaused(.history), !CloudSync.shared.isPaused(.library),
              item.lastPlayedPosition.isFinite, item.lastPlayedPosition >= 0 else { return }
        let checkpoint = CloudPlaybackSync.Checkpoint(
            position: item.lastPlayedPosition, duration: item.duration,
            lastPlayed: item.lastPlayedDate, revision: item.lastPlayedDate ?? Date(), operation: UUID())
        let name = CloudPlaybackSync.recordName(for: item.contentKey)
        var changes = [name: checkpoint]
        addHistoryEvent(for: item, name: name, checkpoint: checkpoint, into: &changes)
        _ = cloudPlayback?.enqueue(changes)
    }

    private func addHistoryEvent(for item: MediaItem, name: String, checkpoint: CloudPlaybackSync.Checkpoint,
                                 into changes: inout [String: CloudPlaybackSync.Checkpoint]) {
        guard let played = item.lastPlayedDate, !item.hasResumePoint,
              item.isWatched || item.lastPlayedPosition == 0 else { return }
        var event = checkpoint
        event.historyTitle = name
        let eventName = CloudPlaybackSync.recordName(for: "history:\(name):\(played.timeIntervalSince1970)")
        changes[eventName] = event
    }
    #endif

    /// The players' background safety checkpoint. Writing the whole library every
    /// five seconds re-encoded it, pushed it to iCloud and re-rendered every library
    /// observer mid-playback; periodic saves now coalesce to one write per interval
    /// while explicit saves stay exact.
    func save(position: TimeInterval, duration: TimeInterval?, for item: MediaItem, periodic: Bool) {
        guard periodic else {
            save(position: position, duration: duration, for: item)
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastWriteUptime[item.contentKey], now - last < Self.periodicWriteInterval { return }
        write(position: position, duration: duration, for: item, immediate: false)
    }

    /// Records the exact current position for the matching persisted library item.
    /// Progress is cleared only when playback actually reaches the end; pausing late
    /// in a title still resumes at that late timestamp.
    func save(position: TimeInterval, duration: TimeInterval?, for item: MediaItem) {
        write(position: position, duration: duration, for: item, immediate: true)
    }

    private func write(position: TimeInterval, duration: TimeInterval?, for item: MediaItem, immediate: Bool) {
        guard item.sourceType != .liveTV, position.isFinite, position >= 0 else { return }
        lastWriteUptime[item.contentKey] = ProcessInfo.processInfo.systemUptime

        // Playback normally adds the resolved item before presenting the player, but
        // direct/deep-link routes can bypass that step. Persist it here as a safety net
        // so every playable title can resume on the next launch.
        if persistedItem(matching: item) == nil {
            library.add(item)
        }
        guard var persisted = persistedItem(matching: item) else { return }

        if let duration = MediaReliabilityPolicy.validDuration(duration)
            ?? MediaReliabilityPolicy.validDuration(persisted.duration) {
            persisted.duration = duration
            // Completion callbacks save the full duration. Do not use a broad
            // percentage threshold here: stopping at 91% or 98% must still resume at
            // the precise checkpoint. Allow only sub-second end-time variance.
            if position >= max(duration - 0.75, 0) {
                persisted.lastPlayedPosition = 0
                persisted.lastPlayedDate = Date()
                library.updateProgress(persisted, immediate: true)
                return
            }
        }

        persisted.lastPlayedPosition = position
        persisted.lastPlayedDate = Date()
        library.updateProgress(persisted, immediate: immediate)
    }

    /// Backward-compatible UUID API for non-player callers.
    func save(position: TimeInterval, duration: TimeInterval?, for itemID: UUID) {
        guard let item = library.item(id: itemID) else { return }
        save(position: position, duration: duration, for: item)
    }

    /// Returns a meaningful resume position for the persisted item (> 5s, not done).
    func resumePosition(for item: MediaItem) -> TimeInterval? {
        guard let persisted = persistedItem(matching: item), persisted.hasResumePoint else { return nil }
        return persisted.lastPlayedPosition
    }

    /// Backward-compatible UUID API for non-player callers.
    func resumePosition(for itemID: UUID) -> TimeInterval? {
        guard let item = library.item(id: itemID) else { return nil }
        return resumePosition(for: item)
    }

    /// Clears progress for a single item (the "Start Over" action).
    func reset(for item: MediaItem) {
        guard var persisted = persistedItem(matching: item) else { return }
        persisted.lastPlayedPosition = 0
        persisted.lastPlayedDate = nil
        library.updateProgress(persisted, immediate: true)
    }

    func reset(for itemID: UUID) {
        guard let item = library.item(id: itemID) else { return }
        reset(for: item)
    }

    /// Prefer exact UUID, then fall back to the stable content key. This is what keeps
    /// resume reliable when a newly resolved stream has a new transient UUID.
    private func persistedItem(matching item: MediaItem) -> MediaItem? {
        library.item(id: item.id)
            ?? library.items.first(where: { $0.contentKey == item.contentKey })
    }
}
