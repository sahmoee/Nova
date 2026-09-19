//
//  NovaChapterBar.swift
//  Nova
//
//  Chapter scrub bar and chapter list sheet for the Nova player.
//  Builds on the existing SkipSegment array already present on MediaItem.
//  Also parses Matroska-style chapter text (CHAPTER01=00:01:23.000 / CHAPTER01NAME=Opening).
//
//  Wire to player:
//  1. Pass the current MediaItem to NovaChapterBar(item:currentPosition:onSeek:).
//  2. Bind currentPosition to your player's current time publisher.
//  3. In onSeek, call player.seek(to:) with the given seconds.
//

import SwiftUI

// MARK: - Chapter model (extends SkipSegment concept)

struct NovaChapter: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var startSeconds: Double
    var endSeconds: Double?   // nil = runs to next chapter / end of item

    var startDisplay: String {
        let s = Int(startSeconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }
}

// MARK: - Chapter parser (builds chapters from SkipSegments)

enum NovaChapterParser {
    /// Converts a MediaItem's skip segments into displayable chapters.
    /// Named segments (intro, outro) become chapter dividers.
    static func chapters(from item: MediaItem) -> [NovaChapter] {
        guard !item.skipSegments.isEmpty else { return [] }
        let sorted = item.skipSegments.sorted { $0.start < $1.start }
        var result: [NovaChapter] = []

        for (i, seg) in sorted.enumerated() {
            let end: Double? = (i + 1 < sorted.count)
                ? sorted[i + 1].start
                : item.duration
            result.append(NovaChapter(
                title: seg.kind.displayName,
                startSeconds: seg.start,
                endSeconds: end
            ))
        }

        // Prepend a "Main" chapter from 0 to first segment when there's a gap.
        if let first = result.first, first.startSeconds > 5 {
            result.insert(NovaChapter(
                title: "Main",
                startSeconds: 0,
                endSeconds: first.startSeconds
            ), at: 0)
        }

        return result
    }

    /// Parses a simple text chapter file (OGG/Matroska format):
    ///   CHAPTER01=00:01:23.000
    ///   CHAPTER01NAME=Opening
    static func parse(text: String) -> [NovaChapter] {
        var times: [Int: Double] = [:]
        var names: [Int: String] = [:]

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.uppercased().hasPrefix("CHAPTER") else { continue }
            let body = String(trimmed.dropFirst("CHAPTER".count))
            let parts = body.components(separatedBy: "=")
            guard parts.count == 2 else { continue }
            let key = parts[0].uppercased()
            let value = parts[1]

            if key.hasSuffix("NAME") {
                if let num = Int(key.dropLast(4)) { names[num] = value }
            } else {
                if let num = Int(key), let secs = parseTimestamp(value) { times[num] = secs }
            }
        }

        return times.keys.sorted().compactMap { num -> NovaChapter? in
            guard let start = times[num] else { return nil }
            return NovaChapter(title: names[num] ?? "Chapter \(num)", startSeconds: start)
        }
    }

    private static func parseTimestamp(_ ts: String) -> Double? {
        let parts = ts.components(separatedBy: ":").flatMap { $0.components(separatedBy: ".") }
        guard parts.count >= 3,
              let h = Double(parts[0]),
              let m = Double(parts[1]),
              let s = Double(parts[2])
        else { return nil }
        let ms = parts.count > 3 ? (Double(parts[3]) ?? 0) / 1000 : 0
        return h * 3600 + m * 60 + s + ms
    }
}

// MARK: - SkipSegmentType display name

// SkipSegment uses `kind: SkipSegmentType` and `start`/`end: TimeInterval`
// (defined in SkipSegmentProvider.swift / MediaItem.swift).
extension SkipSegmentType {
    var displayName: String {
        switch self {
        case .intro:  return "Intro"
        case .outro:  return "Credits"
        default:      return String(describing: self).capitalized
        }
    }
}

// MARK: - Chapter progress bar (overlays the default scrub bar)

struct NovaChapterBar: View {
    let item: MediaItem
    let currentPosition: Double
    var onSeek: ((Double) -> Void)?

    private var chapters: [NovaChapter] { NovaChapterParser.chapters(from: item) }
    private var duration: Double { item.duration ?? 1 }

    @State private var showList = false

    var body: some View {
        if chapters.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                // Current chapter label
                if let current = currentChapter {
                    Button { showList = true } label: {
                        HStack(spacing: 4) {
                            Text(current.title)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.orange)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                // Segmented progress bar
                HStack(spacing: 2) {
                    ForEach(chapters) { chapter in
                        ChapterSegment(
                            chapter: chapter,
                            currentPosition: currentPosition,
                            duration: duration,
                            onTap: { onSeek?(chapter.startSeconds) }
                        )
                    }
                }
                .frame(height: 3)
            }
            .sheet(isPresented: $showList) {
                NovaChapterListSheet(
                    chapters: chapters,
                    currentPosition: currentPosition,
                    onSelect: { onSeek?($0.startSeconds) }
                )
            }
        }
    }

    private var currentChapter: NovaChapter? {
        chapters.last(where: { currentPosition >= $0.startSeconds })
    }
}

private struct ChapterSegment: View {
    let chapter: NovaChapter
    let currentPosition: Double
    let duration: Double
    var onTap: (() -> Void)?

    private var widthFraction: Double {
        guard duration > 0 else { return 0 }
        let start = chapter.startSeconds
        let end = chapter.endSeconds ?? duration
        return (end - start) / duration
    }

    private var fillFraction: Double {
        guard duration > 0 else { return 0 }
        let start = chapter.startSeconds
        let end = chapter.endSeconds ?? duration
        let segLength = max(1, end - start)
        return max(0, min(1, (currentPosition - start) / segLength))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule()
                    .fill(currentPosition >= chapter.startSeconds ? Color.orange : .clear)
                    .frame(width: geo.size.width * fillFraction)
            }
        }
        .frame(maxWidth: .infinity)
        .onTapGesture { onTap?() }
    }
}

// MARK: - Chapter list sheet

struct NovaChapterListSheet: View {
    let chapters: [NovaChapter]
    let currentPosition: Double
    var onSelect: ((NovaChapter) -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(chapters) { chapter in
                Button {
                    onSelect?(chapter)
                    dismiss()
                } label: {
                    HStack {
                        Text(chapter.startDisplay)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .leading)
                        Text(chapter.title)
                            .foregroundStyle(.primary)
                        Spacer()
                        if currentPosition >= chapter.startSeconds,
                           let end = chapter.endSeconds, currentPosition < end {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
