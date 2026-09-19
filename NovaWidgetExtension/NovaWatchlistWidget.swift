//
//  NovaWatchlistWidget.swift
//  Nova / NovaWidgetExtension
//
//  WidgetKit "Continue Watching" widget for the Home Screen and lock screen.
//  Uses the existing WidgetShared / WidgetSnapshot / WidgetEntry types defined
//  in App/WidgetShared.swift — this file must NOT redefine those types.
//
//  Setup:
//  1. Add a Widget Extension target (File → New → Target → Widget Extension).
//  2. Add WidgetShared.swift to BOTH the main app AND the widget extension targets.
//  3. This file belongs in the widget extension target only.
//  4. LibraryStore already calls WidgetShared.write() via writeWidgetSnapshot().
//

import WidgetKit
import SwiftUI

// MARK: - Timeline entry wrapping the shared snapshot

struct NovaWidgetTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

// MARK: - Timeline provider

struct NovaContinueWatchingProvider: TimelineProvider {

    func placeholder(in context: Context) -> NovaWidgetTimelineEntry {
        let placeholder = WidgetSnapshot(
            continueWatching: [
                WidgetEntry(id: "placeholder", title: "Sample Title",
                            subtitle: "S01E04 · 2024", posterURLString: nil,
                            progress: 0.45, deepLink: "nova://")
            ],
            recentlyAdded: [],
            updated: Date()
        )
        return NovaWidgetTimelineEntry(date: Date(), snapshot: placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (NovaWidgetTimelineEntry) -> Void) {
        completion(NovaWidgetTimelineEntry(date: Date(), snapshot: WidgetShared.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NovaWidgetTimelineEntry>) -> Void) {
        let entry = NovaWidgetTimelineEntry(date: Date(), snapshot: WidgetShared.read())
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Widget definition

struct NovaContinueWatchingWidget: Widget {
    let kind = "NovaContinueWatching"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NovaContinueWatchingProvider()) { entry in
            NovaContinueWatchingWidgetView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Continue Watching")
        .description("Pick up where you left off in Nova.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

// MARK: - Widget views

struct NovaContinueWatchingWidgetView: View {
    let entry: NovaWidgetTimelineEntry
    @Environment(\.widgetFamily) private var family

    private var items: [WidgetEntry] { entry.snapshot.continueWatching }

    var body: some View {
        switch family {
        case .systemSmall:
            SmallView(item: items.first)
        case .systemMedium:
            MediumView(items: Array(items.prefix(2)))
        case .accessoryRectangular:
            LockScreenView(item: items.first)
        default:
            LargeView(items: Array(items.prefix(3)))
        }
    }
}

private struct SmallView: View {
    let item: WidgetEntry?

    var body: some View {
        if let item {
            VStack(alignment: .leading, spacing: 6) {
                PosterThumb(urlString: item.posterURLString)
                    .frame(maxHeight: .infinity)
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .foregroundStyle(.white)
                ProgressBar(fraction: item.progress)
                    .frame(height: 3)
            }
            .padding(10)
        } else {
            Text("Nothing in progress")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding()
        }
    }
}

private struct MediumView: View {
    let items: [WidgetEntry]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(items) { item in
                Link(destination: URL(string: item.deepLink) ?? URL(string: "nova://")!) {
                    VStack(alignment: .leading, spacing: 5) {
                        PosterThumb(urlString: item.posterURLString)
                            .frame(maxHeight: .infinity)
                        Text(item.title)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(2)
                            .foregroundStyle(.white)
                        ProgressBar(fraction: item.progress)
                            .frame(height: 2)
                    }
                }
            }
        }
        .padding(12)
    }
}

private struct LargeView: View {
    let items: [WidgetEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Continue Watching", systemImage: "play.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            ForEach(items) { item in
                Link(destination: URL(string: item.deepLink) ?? URL(string: "nova://")!) {
                    HStack(spacing: 10) {
                        PosterThumb(urlString: item.posterURLString)
                            .frame(width: 48, height: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(item.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ProgressBar(fraction: item.progress)
                                .frame(height: 3)
                        }
                        Spacer()
                        Image(systemName: "play.circle.fill")
                            .foregroundStyle(.orange)
                            .font(.title3)
                    }
                }
            }
            Spacer()
        }
        .padding(14)
    }
}

private struct LockScreenView: View {
    let item: WidgetEntry?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "play.fill").font(.caption)
            if let item {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(.caption2.weight(.semibold)).lineLimit(1)
                    Text("\(Int(item.progress * 100))% watched").font(.caption2)
                }
            } else {
                Text("Nova").font(.caption2)
            }
        }
    }
}

private struct PosterThumb: View {
    let urlString: String?
    var body: some View {
        AsyncImage(url: urlString.flatMap { URL(string: $0) }) { phase in
            if let img = phase.image {
                img.resizable().scaledToFill()
            } else {
                Color.gray.opacity(0.3)
                    .overlay(Image(systemName: "film").foregroundStyle(.white.opacity(0.5)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct ProgressBar: View {
    let fraction: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule()
                    .fill(.orange)
                    .frame(width: geo.size.width * max(0, min(1, fraction)))
            }
        }
    }
}

// MARK: - Widget bundle (place in Widget Extension target)

@main
struct NovaWidgetBundle: WidgetBundle {
    var body: some Widget {
        NovaContinueWatchingWidget()
    }
}
