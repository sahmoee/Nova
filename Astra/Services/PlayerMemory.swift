//
//  PlayerMemory.swift
//  Astra
//
//  Remembers which playback engine (VLC or AVPlayer) last played a given title
//  successfully, keyed by the item's stable content key. Some files play better in
//  one engine than the other, so once an engine works for a title we prefer it next
//  time. The user's explicit player preference always overrides this memory.
//

import Foundation

enum PlaybackEngine: String {
    case vlc
    case avPlayer
}

enum PlayerMemory {
    private static let prefix = "player.engine."
    // UserDefaults is documented as thread-safe, but it isn't `Sendable`. Mark the
    // shared instance `nonisolated(unsafe)` to opt out of the concurrency check.
    nonisolated(unsafe) private static let defaults = UserDefaults.standard

    /// Records the engine that successfully started playback for an item.
    static func remember(_ engine: PlaybackEngine, for item: MediaItem) {
        defaults.set(engine.rawValue, forKey: prefix + item.contentKey)
    }

    /// The remembered engine for an item, if any.
    static func engine(for item: MediaItem) -> PlaybackEngine? {
        guard let raw = defaults.string(forKey: prefix + item.contentKey) else { return nil }
        return PlaybackEngine(rawValue: raw)
    }

    /// Clears the remembered engine for an item (e.g. after a failure in that engine).
    static func forget(for item: MediaItem) {
        defaults.removeObject(forKey: prefix + item.contentKey)
    }
}
