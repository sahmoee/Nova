//
//  PlaybackProgressStore.swift
//  FrameTV
//
//  Saves and restores playback positions. Writes back into the LibraryStore so
//  Continue Watching stays in sync. Progress is saved on a cadence by the player.
//

import Foundation

@MainActor
final class PlaybackProgressStore: ObservableObject {

    private unowned let library: LibraryStore

    init(library: LibraryStore) {
        self.library = library
    }

    /// Records the current position and timestamp for an item.
    /// Automatically marks the item watched (position cleared) at >= 90%.
    func save(position: TimeInterval, duration: TimeInterval?, for itemID: UUID) {
        guard var item = library.item(id: itemID) else { return }

        if let duration, duration > 0 {
            item.duration = duration
            let fraction = position / duration
            if fraction >= 0.9 {
                // Treat as completed: clear resume so it leaves Continue Watching.
                item.lastPlayedPosition = 0
                item.lastPlayedDate = Date()
                library.update(item)
                return
            }
        }

        item.lastPlayedPosition = position
        item.lastPlayedDate = Date()
        library.update(item)
    }

    /// Returns a resume position if one is meaningful (> 30s, not finished).
    func resumePosition(for itemID: UUID) -> TimeInterval? {
        guard let item = library.item(id: itemID), item.hasResumePoint else { return nil }
        return item.lastPlayedPosition
    }

    /// Clears progress for a single item (the "Start Over" action).
    func reset(for itemID: UUID) {
        guard var item = library.item(id: itemID) else { return }
        item.lastPlayedPosition = 0
        library.update(item)
    }
}
