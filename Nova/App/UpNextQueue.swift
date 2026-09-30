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

// MARK: - Legacy store

/// Nova 1.7 briefly shipped this separate queue file. Nothing in the app added to it, so
/// the library's own queue (Home "Up Next", title detail "Queue", iCloud-synced) is the
/// one real queue. Any legacy entries are moved into it once and the file is removed.
@MainActor
final class NovaUpNextQueue {
    static let shared = NovaUpNextQueue()

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nova", isDirectory: true)
        return dir.appendingPathComponent("upnext.json")
    }()

    private init() {}

    /// Returns how many legacy entries were matched to library items and queued.
    @discardableResult
    func migrateLegacyEntries(into library: LibraryStore) -> Int {
        guard let data = try? Data(contentsOf: fileURL) else { return 0 }
        guard let saved = try? JSONDecoder().decode([MediaItem].self, from: data) else {
            // Unreadable legacy data is left in place rather than destroyed.
            return 0
        }
        let ids = saved.compactMap { legacy in
            library.item(id: legacy.id)?.id ?? library.items.first(where: { $0.contentKey == legacy.contentKey })?.id
        }
        library.addToQueue(ids: ids)
        try? FileManager.default.removeItem(at: fileURL)
        return ids.count
    }
}

// MARK: - Up Next Sheet

/// Settings → Playback Tools → Up Next Queue. Edits the same queue Home and title
/// detail use, so reordering and removal here are reflected everywhere.
struct NovaUpNextQueueView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var nav: NavigationCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false

    /// Called when the user taps a queue item. Defaults to opening the title.
    var onPlay: ((MediaItem) -> Void)?

    var body: some View {
        NavigationStack {
            Group {
                if library.queuedEntries.isEmpty {
                    ContentUnavailableView(
                        "Up Next is Empty",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Add titles from their detail page, or long-press a title in Library and choose Add to Queue.")
                    )
                } else {
                    List {
                        ForEach(library.queuedEntries) { item in
                            QueueRow(item: item, onPlay: { open(item) })
                                .contextMenu {
                                    Button { library.moveToFrontOfQueue(item) } label: {
                                        Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                                    }
                                    Button(role: .destructive) { library.removeFromQueue(item) } label: {
                                        Label("Remove from Queue", systemImage: "minus.circle")
                                    }
                                }
                        }
                        .onDelete { offsets in
                            let entries = library.queuedEntries
                            for index in offsets where entries.indices.contains(index) {
                                library.removeFromQueue(entries[index])
                            }
                        }
                        .onMove { library.moveInQueue(from: $0, to: $1) }
                    }
                    #if os(iOS)
                    .environment(\.editMode, .constant(.active))
                    #endif
                }
            }
            .navigationTitle("Up Next")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if !library.queuedEntries.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Clear", role: .destructive) { confirmClear = true }
                    }
                }
            }
            .confirmationDialog("Clear Up Next?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear Queue", role: .destructive) { library.clearQueue() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Titles stay in your library; only the queue is emptied.")
            }
            .onAppear { NovaUpNextQueue.shared.migrateLegacyEntries(into: library) }
        }
        .presentationDetents([.medium, .large])
    }

    private func open(_ item: MediaItem) {
        if let onPlay { onPlay(item); return }
        dismiss()
        nav.handle(.content(contentKey: item.contentKey, isShow: item.isSeries))
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
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayTitle)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Text(item.hasResumePoint ? "In progress · \(item.subtitleLine)" : item.subtitleLine)
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
                    .foregroundStyle(Theme.Colors.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(item.displayTitle)")
        }
        .padding(.vertical, 2)
    }
}
