//
//  NovaBookmarkStore.swift
//  Nova
//
//  Timestamp bookmarks for any MediaItem. Persisted to Application Support.
//  Wire to the player: call BookmarkStore.shared.add(...) from the
//  "Bookmark" button, and present NovaBookmarksView from library/detail screen.
//

import SwiftUI

// MARK: - Model

struct NovaBookmark: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var mediaItemID: UUID
    var mediaTitle: String
    var seriesTitle: String?
    var episodeLabel: String?
    var posterURLString: String?
    var positionSeconds: Double
    var note: String
    var createdAt: Date = Date()

    var positionDisplay: String {
        let s = Int(positionSeconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }

    var displayTitle: String {
        if let series = seriesTitle, let ep = episodeLabel {
            return "\(series) · \(ep)"
        }
        return mediaTitle
    }
}

// MARK: - Store

@MainActor
final class NovaBookmarkStore: ObservableObject {
    static let shared = NovaBookmarkStore()

    @Published private(set) var bookmarks: [NovaBookmark] = []

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nova", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("bookmarks.json")
    }()

    private init() { load() }

    func add(
        item: MediaItem,
        positionSeconds: Double,
        note: String = ""
    ) {
        let bookmark = NovaBookmark(
            mediaItemID: item.id,
            mediaTitle: item.title,
            seriesTitle: item.seriesTitle,
            episodeLabel: item.episode?.label,
            posterURLString: item.posterURL?.absoluteString,
            positionSeconds: positionSeconds,
            note: note
        )
        bookmarks.insert(bookmark, at: 0)
        save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func delete(_ bookmark: NovaBookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        save()
    }

    func delete(offsets: IndexSet) {
        bookmarks.remove(atOffsets: offsets)
        save()
    }

    func bookmarks(for item: MediaItem) -> [NovaBookmark] {
        bookmarks.filter { $0.mediaItemID == item.id }
            .sorted { $0.positionSeconds < $1.positionSeconds }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode([NovaBookmark].self, from: data)
        else { return }
        bookmarks = saved
    }
}

// MARK: - Add Bookmark Sheet (shown from player)

struct NovaAddBookmarkSheet: View {
    let item: MediaItem
    let positionSeconds: Double
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @FocusState private var noteFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: "bookmark.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayTitle)
                                .font(.headline)
                            Text(formattedPosition)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Note (optional)") {
                    TextField("What's happening here?", text: $note, axis: .vertical)
                        .focused($noteFieldFocused)
                        .lineLimit(3, reservesSpace: true)
                }
            }
            .navigationTitle("Add Bookmark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        NovaBookmarkStore.shared.add(
                            item: item,
                            positionSeconds: positionSeconds,
                            note: note.trimmingCharacters(in: .whitespaces)
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear { noteFieldFocused = true }
        }
        .presentationDetents([.medium])
    }

    private var formattedPosition: String {
        let s = Int(positionSeconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 { return String(format: "at %d:%02d:%02d", h, m, sec) }
        return String(format: "at %d:%02d", m, sec)
    }
}

// MARK: - Bookmarks List View (shown from detail/library)

struct NovaBookmarksView: View {
    let item: MediaItem?   // nil = show all bookmarks
    @StateObject private var store = NovaBookmarkStore.shared

    /// Called when user taps a bookmark — jump to position in player.
    var onSelect: ((NovaBookmark) -> Void)?

    private var displayed: [NovaBookmark] {
        if let item {
            return store.bookmarks(for: item)
        }
        return store.bookmarks
    }

    var body: some View {
        Group {
            if displayed.isEmpty {
                ContentUnavailableView(
                    "No Bookmarks",
                    systemImage: "bookmark",
                    description: Text(item != nil
                        ? "Tap the bookmark button in the player to save a moment."
                        : "Bookmarks you add while watching will appear here.")
                )
            } else {
                List {
                    ForEach(displayed) { bookmark in
                        Button {
                            onSelect?(bookmark)
                        } label: {
                            BookmarkRow(bookmark: bookmark, showTitle: item == nil)
                        }
                        .foregroundStyle(.primary)
                    }
                    .onDelete { store.delete(offsets: $0) }
                }
            }
        }
        .navigationTitle("Bookmarks")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct BookmarkRow: View {
    let bookmark: NovaBookmark
    let showTitle: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bookmark.fill")
                .foregroundStyle(.orange)
                .font(.subheadline)

            VStack(alignment: .leading, spacing: 3) {
                if showTitle {
                    Text(bookmark.displayTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(bookmark.positionDisplay)
                    .font(.headline.monospacedDigit())
                if !bookmark.note.isEmpty {
                    Text(bookmark.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Text(bookmark.createdAt, style: .date)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
