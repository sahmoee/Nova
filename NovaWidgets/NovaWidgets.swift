//
//  NovaWidgets.swift
//  NovaWidgets (widget extension target)
//
//  Home-screen widgets for iOS/iPadOS: Continue Watching and Recently Added. The data
//  comes from the shared App Group snapshot the app writes (WidgetShared). Tapping a
//  widget opens the app to that title via a nova:// deep link.
//
//  Poster images are downloaded in the timeline provider (which has time to do network
//  work) and handed to the views as ready bytes. AsyncImage is intentionally NOT used:
//  widgets render in a brief snapshot pass where async network loads don't finish, so
//  AsyncImage shows only its placeholder. Pre-fetching is the supported approach.
//
//  IMPORTANT - Xcode setup:
//   • This file belongs to the NovaWidgets extension target only.
//   • WidgetShared.swift must be a member of BOTH the app and this extension target.
//   • Both targets must have the retained App Group "group.astra.ios" enabled.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline

/// Wraps a WidgetKit completion handler so it can be captured by a `Task` under
/// Swift 6 strict concurrency. Safe because the completion is called exactly once,
/// off the render pass.
private struct SendableCompletion<T>: @unchecked Sendable {
    let call: (T) -> Void
    init(_ call: @escaping (T) -> Void) { self.call = call }
}

struct NovaProvider: TimelineProvider {
    func placeholder(in context: Context) -> NovaTimelineEntry {
        NovaTimelineEntry(date: Date(), snapshot: .empty, posters: [:])
    }

    func getSnapshot(in context: Context, completion: @escaping (NovaTimelineEntry) -> Void) {
        let snapshot = WidgetShared.read()
        let done = SendableCompletion(completion)
        Task {
            let posters = await PosterLoader.load(for: snapshot)
            done.call(NovaTimelineEntry(date: Date(), snapshot: snapshot, posters: posters))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NovaTimelineEntry>) -> Void) {
        let snapshot = WidgetShared.read()
        let done = SendableCompletion(completion)
        Task {
            let posters = await PosterLoader.load(for: snapshot)
            let entry = NovaTimelineEntry(date: Date(), snapshot: snapshot, posters: posters)
            // Refresh every 30 minutes as a fallback; the app also reloads on library change.
            let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
            done.call(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

struct NovaTimelineEntry: TimelineEntry, Sendable {
    let date: Date
    let snapshot: WidgetSnapshot
    /// Poster image bytes keyed by entry id, pre-fetched so views render instantly.
    let posters: [String: Data]
}

/// Downloads poster images for every entry in a snapshot, with a short per-image
/// timeout so a slow URL can't stall the whole timeline. Runs off the render pass.
private enum PosterLoader {
    static func load(for snapshot: WidgetSnapshot) async -> [String: Data] {
        let entries = (snapshot.continueWatching + snapshot.recentlyAdded)
        // De-dupe by id so we don't fetch the same poster twice.
        var seen = Set<String>()
        let unique = entries.filter { seen.insert($0.id).inserted }

        var result: [String: Data] = [:]
        await withTaskGroup(of: (String, Data?).self) { group in
            for entry in unique {
                guard let url = entry.posterURL else { continue }
                group.addTask {
                    (entry.id, await fetch(url))
                }
            }
            for await (id, data) in group {
                if let data { result[id] = data }
            }
        }
        return result
    }

    private static func fetch(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return data
        } catch {
            return nil
        }
    }
}

// MARK: - Poster cell

private struct PosterCell: View {
    let entry: WidgetEntry
    let posterData: Data?
    var showProgress: Bool
    var titleFont: Font

    var body: some View {
        Link(destination: URL(string: entry.deepLink) ?? URL(string: "nova://library")!) {
            VStack(alignment: .leading, spacing: 5) {
                poster
                    .aspectRatio(2.0/3.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                    )
                    .overlay(alignment: .bottom) {
                        if showProgress, entry.progress > 0.01 {
                            ProgressBar(progress: entry.progress)
                                .padding(.horizontal, 5)
                                .padding(.bottom, 5)
                        }
                    }

                Text(entry.title)
                    .font(titleFont)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder private var poster: some View {
        if let data = posterData, let uiImage = UIImage(data: data) {
            Color.clear.overlay(
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            )
            .clipped()
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.gray.opacity(0.25))
            .overlay(
                Image(systemName: "film")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            )
    }
}

/// A slim rounded progress bar shown along the bottom of a Continue Watching poster.
private struct ProgressBar: View {
    let progress: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.55))
                Capsule().fill(.white)
                    .frame(width: max(3, geo.size.width * min(progress, 1)))
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Widget views

private struct RowWidgetView: View {
    let title: String
    let systemImage: String
    let entries: [WidgetEntry]
    let posters: [String: Data]
    let showProgress: Bool
    @Environment(\.widgetFamily) private var family

    /// How many posters to show per size. Fewer items = bigger posters.
    private var count: Int {
        switch family {
        case .systemLarge:  return 4   // tall frame makes these large
        case .systemMedium: return 3   // fewer, bigger posters than before
        default:            return 3
        }
    }

    private var titleFont: Font {
        family == .systemLarge ? .subheadline : .caption2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 14 : 9) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .kerning(0.5)
                Spacer()
            }
            .foregroundStyle(.secondary)

            if entries.isEmpty {
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "film.stack")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                        Text("Nothing here yet")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                Spacer(minLength: 0)
            } else if family == .systemLarge {
                // Large: a 2-row grid (up to 8) so the tall frame fills elegantly.
                Spacer(minLength: 0)
                let cols = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
                LazyVGrid(columns: cols, spacing: 14) {
                    ForEach(entries.prefix(8)) { entry in
                        PosterCell(entry: entry,
                                   posterData: posters[entry.id],
                                   showProgress: showProgress,
                                   titleFont: titleFont)
                    }
                }
                Spacer(minLength: 0)
            } else {
                // Medium/small: a single centered row of larger posters.
                Spacer(minLength: 0)
                HStack(alignment: .top, spacing: 10) {
                    ForEach(entries.prefix(count)) { entry in
                        PosterCell(entry: entry,
                                   posterData: posters[entry.id],
                                   showProgress: showProgress,
                                   titleFont: titleFont)
                    }
                    if entries.count < count {
                        ForEach(0..<(count - entries.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(family == .systemLarge ? 18 : 14)
    }
}

// MARK: - Widget definitions

struct ContinueWatchingWidget: Widget {
    let kind = "NovaContinueWatching"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NovaProvider()) { entry in
            RowWidgetView(title: "Continue Watching",
                          systemImage: "play.circle",
                          entries: entry.snapshot.continueWatching,
                          posters: entry.posters,
                          showProgress: true)
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Continue Watching")
        .description("Pick up where you left off.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct RecentlyAddedWidget: Widget {
    let kind = "NovaRecentlyAdded"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NovaProvider()) { entry in
            RowWidgetView(title: "Recently Added",
                          systemImage: "sparkles",
                          entries: entry.snapshot.recentlyAdded,
                          posters: entry.posters,
                          showProgress: false)
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Recently Added")
        .description("Your newest titles.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Bundle entry point

@main
struct NovaWidgetBundle: WidgetBundle {
    var body: some Widget {
        ContinueWatchingWidget()
        RecentlyAddedWidget()
    }
}
