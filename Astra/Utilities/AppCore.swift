//
//  AppCore.swift
//  Astra
//
//  Small app-wide foundations:
//   - PrefKey: one namespace for UserDefaults/iCloud KVS keys, replacing stringly-
//     typed keys scattered across services. Raw values are unchanged, so existing
//     stored data is picked up exactly as before.
//   - Coders: shared JSONEncoder/JSONDecoder instances for hot paths, avoiding a
//     fresh allocation on every encode/decode call.
//   - Signposts: os_signpost instrumentation helpers for profiling shelf loads and
//     stream resolution in Instruments (negligible cost when not recording).
//

import Foundation
import os

// MARK: - Preference keys

/// Central namespace for persisted preference keys. Raw values must never change —
/// they are the on-disk/iCloud identity of each setting.
enum PrefKey {
    static let aiWorkerURL   = "ai.workerURL"
    static let aiLastFeature = "ai.lastFeature.v1"
    static let streamsCachedOnly = "streams.cachedOnly.v1"
    static let homeShelves   = "home.shelves.v1"
    static let libraryQueue  = "library.queue.v1"
    static let cloudLibrary  = "cloud.library.v1"
    static let cloudLibraryRevision = "cloud.library.revision"
    static let cloudCollections     = "cloud.collections.v1"
}

// MARK: - Shared coders

/// Shared JSON coders for plain (no custom strategy) encoding/decoding. Services
/// that need special date strategies keep their own configured instances.
enum Coders {
    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()
}

// MARK: - Signposts

/// Lightweight wrappers around OSSignposter so call sites stay one-liners.
/// View intervals in Instruments under the com.astra.app subsystem.
enum Signposts {
    static let shelf  = OSSignposter(subsystem: "com.astra.app", category: "shelf")
    static let stream = OSSignposter(subsystem: "com.astra.app", category: "stream")

    /// Measures an async operation as a signpost interval.
    static func measure<T>(_ poster: OSSignposter, _ name: StaticString,
                           _ operation: () async -> T) async -> T {
        let state = poster.beginInterval(name)
        defer { poster.endInterval(name, state) }
        return await operation()
    }
}
