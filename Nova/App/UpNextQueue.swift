//
//  NovaUpNextQueue.swift
//  Nova
//
//  Smart "Up Next" queue: drag-and-drop ordering, persisted between sessions,
//  auto-advances to the next item when playback completes.
//
//  Usage:
//  1. Add items: NovaUpNextQueue.shared.add(item)  /  .playNext(item)
//  2. Advance:   NovaUpNextQueue.shared.advance()   (call on playback complete)
//  3. Present:   NovaUpNextQueueView()
//

import SwiftUI

// MARK: - Store

@MainActor
final class NovaUpNextQueue: ObservableObject {
    static let shared = NovaUpNextQueue()

    @Published private(set) var items: [MediaItem] = []

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nova", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("upnext.json")
    }()

    private init() { load() }

    // MARK: - Mutations

    /// Add to end of queue.
    func add(_ item: MediaItem) {
        guard !items.contains(where: { $0.contentKey == item.contentKey }) else { return }
        items.append(item)
        save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Insert at front (Play Next).
    func playNext(_ item: MediaItem) {
        items.removeAll { $0.contentKey == item.contentKey }
        items.insert(item, at: 0)
        save()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Remove a specific item.
    func remove(_ item: MediaItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func remove(offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        save()
    }

    func move(from: IndexSet, to: Int) {
        items.move(fromOffsets: from, toOffset: to)
        save()
    }

    func clear() {
        items = []
        save()
    }

    /// Returns the next item and removes it from the queue.
    @discardableResult
    func advance() -> MediaItem? {
        guard !items.isEmpty else { return nil }
        let next = items.removeFirst()
        save()
        return next
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode([MediaItem].self, from: data)
        else { return }
        items = saved
    }
}

// MARK: - Up Next Sheet

struct NovaUpNextQueueView: View {
    @StateObject private var queue = NovaUpNextQueue.shared
    @Environment(\.dismiss) private var dismiss

    /// Called when the user taps a queue item to play it immediately.
    var onPlay: ((MediaItem) -> Void)?

    var body: some View {
        NavigationStack {
            Group {
                if queue.items.isEmpty {
                    ContentUnavailableView(
                        "Up Next is Empty",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Long-press any title and choose \"Play Next\" or \"Add to Queue\".")
                    )
                } else {
                    List {
                        ForEach(queue.items) { item in
                            QueueRow(item: item, onPlay: {
                                queue.remove(item)
                                onPlay?(item)
                                dismiss()
                            })
                        }
                        .onDelete { queue.remove(offsets: $0) }
                        .onMove { queue.move(from: $0, to: $1) }
                    }
                    .environment(\.editMode, .constant(.active))
                }
            }
            .navigationTitle("Up Next")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if !queue.items.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Clear", role: .destructive) {
                            queue.clear()
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct QueueRow: View {
    let item: MediaItem
    var onPlay: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: item.posterURL) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFill()
                } else {
                    Color.secondary.opacity(0.2)
                }
            }
            .frame(width: 40, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayTitle)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Text(item.subtitleLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                onPlay?()
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Context menu actions (add to any MediaItem row)

extension View {
    /// Adds "Play Next" and "Add to Queue" context menu items for a MediaItem.
    func novaQueueActions(for item: MediaItem) -> some View {
        contextMenu {
            Button {
                NovaUpNextQueue.shared.playNext(item)
            } label: {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            Button {
                NovaUpNextQueue.shared.add(item)
            } label: {
                Label("Add to Queue", systemImage: "text.badge.plus")
            }
        }
    }
}
