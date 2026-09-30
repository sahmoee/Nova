//
//  PlayerMemory.swift
//  Nova
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
    /// One bounded dictionary instead of one UserDefaults key per title: content keys
    /// can be long URLs, and a large library used to leave thousands of keys behind.
    private static let storeKey = "player.engine.memory.v2"
    private static let orderKey = "player.engine.memory.order.v2"
    static let maximumEntries = 500
    // UserDefaults is documented as thread-safe, but it isn't `Sendable`. Mark the
    // shared instance `nonisolated(unsafe)` to opt out of the concurrency check.
    nonisolated(unsafe) private static let defaults = UserDefaults.standard

    /// Records the engine that successfully started playback for an item.
    static func remember(_ engine: PlaybackEngine, for item: MediaItem) {
        let key = item.contentKey
        var store = defaults.dictionary(forKey: storeKey) as? [String: String] ?? [:]
        var order = defaults.stringArray(forKey: orderKey) ?? []
        store[key] = engine.rawValue
        order.removeAll { $0 == key }
        order.append(key)
        let evicted = pruned(order: order, limit: maximumEntries)
        for old in evicted { store[old] = nil }
        order.removeFirst(evicted.count)
        defaults.set(store, forKey: storeKey)
        defaults.set(order, forKey: orderKey)
        defaults.removeObject(forKey: prefix + key)
    }

    /// The remembered engine for an item, if any. Older builds' per-title keys are
    /// still honored and moved into the bounded store on first read.
    static func engine(for item: MediaItem) -> PlaybackEngine? {
        let key = item.contentKey
        if let raw = (defaults.dictionary(forKey: storeKey) as? [String: String])?[key] {
            return PlaybackEngine(rawValue: raw)
        }
        guard let legacy = defaults.string(forKey: prefix + key), let engine = PlaybackEngine(rawValue: legacy) else { return nil }
        remember(engine, for: item)
        return engine
    }

    /// Clears the remembered engine for an item (e.g. after a failure in that engine).
    static func forget(for item: MediaItem) {
        let key = item.contentKey
        var store = defaults.dictionary(forKey: storeKey) as? [String: String] ?? [:]
        var order = defaults.stringArray(forKey: orderKey) ?? []
        store[key] = nil
        order.removeAll { $0 == key }
        defaults.set(store, forKey: storeKey)
        defaults.set(order, forKey: orderKey)
        defaults.removeObject(forKey: prefix + key)
    }

    /// Oldest keys beyond the limit (the order array is oldest first).
    static func pruned(order: [String], limit: Int) -> [String] {
        guard order.count > limit else { return [] }
        return Array(order.prefix(order.count - limit))
    }
}
