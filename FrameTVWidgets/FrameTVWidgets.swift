//
//  FrameTVWidgets.swift
//  FrameTVWidgets (widget extension target)
//
//  Home-screen widgets for iOS/iPadOS: Continue Watching and Recently Added. The data
//  comes from the shared App Group snapshot the app writes (WidgetShared). Tapping a
//  widget opens the app to that title via a frametv:// deep link.
//
//  IMPORTANT — Xcode setup (see the delivery notes):
//   • This file belongs to the FrameTVWidgets extension target only.
//   • WidgetShared.swift must be a member of BOTH the app and this extension target.
//   • Both targets must have the App Group "group.com.frametv.shared" enabled.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline

struct FrameTVProvider: TimelineProvider {
    func placeholder(in context: Context) -> FrameTVTimelineEntry {
        FrameTVTimelineEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (FrameTVTimelineEntry) -> Void) {
        completion(FrameTVTimelineEntry(date: Date(), snapshot: WidgetShared.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FrameTVTimelineEntry>) -> Void) {
        let entry = FrameTVTimelineEntry(date: Date(), snapshot: WidgetShared.read())
        // Refresh every 30 minutes as a fallback; the app also reloads on library change.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct FrameTVTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

// MARK: - Shared poster cell

private struct PosterCell: View {
    let entry: WidgetEntry
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
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(entry.title)
                    .font(.caption2).fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
        }
    }

    @ViewBuilder private var poster: some View {
        if let url = entry.posterURL {
            // Widgets can't async-load images at render; use AsyncImage which
            // WidgetKit snapshots once loaded, with a colored placeholder.
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(2/3, contentMode: .fill)
            } placeholder: {
                placeholder
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.gray.opacity(0.3))
            .aspectRatio(2/3, contentMode: .fill)
            .overlay(Image(systemName: "film").foregroundStyle(.secondary))
    }
}

// MARK: - Widget views

private struct RowWidgetView: View {
    let title: String
    let systemImage: String
    let entries: [WidgetEntry]
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
                HStack(spacing: 8) {
                    ForEach(entries.prefix(count)) { entry in
                        PosterCell(entry: entry, showProgress: showProgress)
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
