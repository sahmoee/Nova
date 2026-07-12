//
//  PlaybackProgressStore.swift
//  Astra
//
//  Saves and restores playback positions. Progress is resolved by the stable content
//  identity as well as UUID, because stream resolution can create a fresh MediaItem
//  instance while the library intentionally keeps the original persisted UUID.
//

import Foundation

@MainActor
final class PlaybackProgressStore: ObservableObject {

    private unowned let library: LibraryStore

    init(library: LibraryStore) {
        self.library = library
    }

    /// Records the exact current position for the matching persisted library item.
    /// Progress is cleared only when playback actually reaches the end; pausing late
    /// in a title still resumes at that late timestamp.
    func save(position: TimeInterval, duration: TimeInterval?, for item: MediaItem) {
        guard position.isFinite, position >= 0 else { return }

        // Playback normally adds the resolved item before presenting the player, but
        // direct/deep-link routes can bypass that step. Persist it here as a safety net
        // so every playable title can resume on the next launch.
        if persistedItem(matching: item) == nil {
            library.add(item)
        }
        guard var persisted = persistedItem(matching: item) else { return }

        if let duration, duration.isFinite, duration > 0 {
            persisted.duration = duration
            // Completion callbacks save the full duration. Do not use a broad
            // percentage threshold here: stopping at 91% or 98% must still resume at
            // the precise checkpoint. Allow only sub-second end-time variance.
            if position >= max(duration - 0.75, 0) {
                persisted.lastPlayedPosition = 0
                persisted.lastPlayedDate = Date()
                library.update(persisted)
                return
            }
        }

        persisted.lastPlayedPosition = position
        persisted.lastPlayedDate = Date()
        library.update(persisted)
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
        library.update(persisted)
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
