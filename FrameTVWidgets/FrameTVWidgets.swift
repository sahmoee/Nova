//
//  FrameTVWidgets.swift
//  FrameTVWidgets (widget extension target)
//
//  Home-screen widgets for iOS/iPadOS: Continue Watching and Recently Added. The data
//  comes from the shared App Group snapshot the app writes (WidgetShared). Tapping a
//  widget opens the app to that title via a frametv:// deep link.
//
//  Poster images are downloaded in the timeline provider (which has time to do network
//  work) and handed to the views as ready bytes. AsyncImage is intentionally NOT used:
//  widgets render in a brief snapshot pass where async network loads don't finish, so
//  AsyncImage shows only its placeholder. Pre-fetching is the supported approach.
//
//  IMPORTANT - Xcode setup:
//   • This file belongs to the FrameTVWidgets extension target only.
//   • WidgetShared.swift must be a member of BOTH the app and this extension target.
//   • Both targets must have the App Group "group.com.frametv.shared" enabled.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline

struct FrameTVProvider: TimelineProvider {
    func placeholder(in context: Context) -> FrameTVTimelineEntry {
        FrameTVTimelineEntry(date: Date(), snapshot: .empty, posters: [:])
    }

    func getSnapshot(in context: Context, completion: @escaping (FrameTVTimelineEntry) -> Void) {
        let snapshot = WidgetShared.read()
        Task {
            let posters = await PosterLoader.load(for: snapshot)
            completion(FrameTVTimelineEntry(date: Date(), snapshot: snapshot, posters: posters))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FrameTVTimelineEntry>) -> Void) {
        let snapshot = WidgetShared.read()
        Task {
            let posters = await PosterLoader.load(for: snapshot)
            let entry = FrameTVTimelineEntry(date: Date(), snapshot: snapshot, posters: posters)
            // Refresh every 30 minutes as a fallback; the app also reloads on library change.
            let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

struct FrameTVTimelineEntry: TimelineEntry {
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

    var body: some View {
        Link(destination: URL(string: entry.deepLink) ?? URL(string: "frametv://library")!) {
            VStack(alignment: .leading, spacing: 4) {
                ZStack(alignment: .bottom) {
                    poster
                    if showProgress, entry.progress > 0.01 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(.black.opacity(0.5))
                                Rectangle().fill(.white)
                                    .frame(width: geo.size.width * entry.progress)
                            }
                            .frame(height: 3)
                        }
                        .frame(height: 3)
                    }
                }
                .aspectRatio(2.0/3.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(entry.title)
                    .font(.caption2).fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
        }
    }

    @ViewBuilder private var poster: some View {
        if let data = posterData, let uiImage = UIImage(data: data) {
            // Pre-fetched bytes render immediately. Fill + clip keeps 2:3 without stretch.
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
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.gray.opacity(0.3))
            .overlay(Image(systemName: "film").foregroundStyle(.secondary))
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

    private var count: Int { family == .systemLarge ? 6 : (family == .systemMedium ? 4 : 2) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(.secondary)
            if entries.isEmpty {
                Spacer()
                Text("Nothing here yet")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(entries.prefix(count)) { entry in
                        PosterCell(entry: entry,
                                   posterData: posters[entry.id],
                                   showProgress: showProgress)
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Widget definitions

struct ContinueWatchingWidget: Widget {
    let kind = "FrameTVContinueWatching"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FrameTVProvider()) { entry in
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
    let kind = "FrameTVRecentlyAdded"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FrameTVProvider()) { entry in
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
struct FrameTVWidgetBundle: WidgetBundle {
    var body: some Widget {
        ContinueWatchingWidget()
        RecentlyAddedWidget()
    }
}
