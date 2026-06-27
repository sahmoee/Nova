//
//  LibraryStore.swift
//  FrameTV
//
//  Owns the unified media library. Persists to a local Codable JSON file in
//  Application Support. (SwiftData can replace this later behind the same API.)
//
//  Marked @MainActor because it publishes UI state.
//

import Foundation
import Combine

@MainActor
final class LibraryStore: ObservableObject {

    @Published private(set) var items: [MediaItem] = []

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(filename: String = "library.json") {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        // Ensure the directory exists.
        try? FileManager.default.createDirectory(
            at: support, withIntermediateDirectories: true
        )
        self.fileURL = support.appendingPathComponent(filename)

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        load()
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            items = []
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            items = try decoder.decode([MediaItem].self, from: data)
        } catch {
            // Corrupt/old format: start clean rather than crash.
            items = []
        }
    }

    private func persist() {
        do {
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Persistence failure shouldn't crash the UI; surface elsewhere if needed.
        }
    }

    // MARK: - CRUD

    func add(_ item: MediaItem) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = item
        } else {
            items.insert(item, at: 0)
        }
        persist()
    }

    func update(_ item: MediaItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx] = item
        persist()
    }

    func remove(_ item: MediaItem) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        persist()
    }

    func toggleFavorite(_ item: MediaItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].isFavorite.toggle()
        persist()
    }

    func clearAll() {
        items.removeAll()
        persist()
    }

    /// Resets only watch progress across the whole library.
    func clearWatchHistory() {
        for idx in items.indices {
            items[idx].lastPlayedPosition = 0
            items[idx].lastPlayedDate = nil
        }
        persist()
    }

    // MARK: - Queries (used by Home/Library rows)

    var favorites: [MediaItem] {
        items.filter { $0.isFavorite }
    }

    var continueWatching: [MediaItem] {
        items
            .filter { $0.hasResumePoint }
            .sorted { ($0.lastPlayedDate ?? .distantPast) > ($1.lastPlayedDate ?? .distantPast) }
    }

    var recentlyAdded: [MediaItem] {
        items.sorted { $0.addedDate > $1.addedDate }
    }

    func items(for source: SourceType) -> [MediaItem] {
        items.filter { $0.sourceType == source }
    }

    func item(id: UUID) -> MediaItem? {
        items.first { $0.id == id }
    }
}
