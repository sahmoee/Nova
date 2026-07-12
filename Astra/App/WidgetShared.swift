//
//  WidgetShared.swift
//  Astra
//
//  Data shared between the app and its iOS/iPadOS widget extension. Widgets run in a
//  separate process and can't read the app's in-memory library, so the app writes a
//  small snapshot to a shared App Group container and the widget reads it.
//
//  IMPORTANT: This file must be a member of BOTH the app target AND the widget
//  extension target (set Target Membership in Xcode for both).
//

import Foundation
#if os(iOS)
import WidgetKit
#endif

/// The App Group identifier shared by the app and the widget. This must match the
/// App Group you create in the Apple Developer portal and enable on both targets.
enum WidgetShared {
    static let appGroup = "group.com.astra.shared"
    private static let snapshotFile = "widget_snapshot.json"

    /// The shared container URL, or nil if the App Group isn't configured.
    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    /// Writes the snapshot to the shared container. Safe to call often; cheap.
    static func write(_ snapshot: WidgetSnapshot) {
        guard let url = containerURL?.appendingPathComponent(snapshotFile) else { return }
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Non-fatal: the widget will just show its placeholder.
        }
    }

    /// Reads the snapshot from the shared container, or an empty snapshot if none.
    static func read() -> WidgetSnapshot {
        guard let url = containerURL?.appendingPathComponent(snapshotFile),
              let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else { return .empty }
        return snap
    }
}

/// A compact, Codable view of the few titles a widget needs to render. Keeps the
/// shared payload tiny and independent of the app's full MediaItem model.
struct WidgetSnapshot: Codable, Equatable {
    var continueWatching: [WidgetEntry]
    var recentlyAdded: [WidgetEntry]
    var updated: Date

    static let empty = WidgetSnapshot(continueWatching: [], recentlyAdded: [], updated: .distantPast)
}

/// One title in a widget.
struct WidgetEntry: Codable, Equatable, Identifiable {
    var id: String            // stable content key
    var title: String
    var subtitle: String      // e.g. "Movie · 2017" or "S2 E4"
    var posterURLString: String?
    var progress: Double      // 0...1, for Continue Watching
    var deepLink: String      // astra:// URL to open this title

    var posterURL: URL? { posterURLString.flatMap(URL.init(string:)) }
}

/// Asks WidgetKit to refresh Astra's widgets. iOS-only; a no-op on tvOS.
enum WidgetRefresher {
    #if os(iOS)
    static func reload() {
        WidgetCenter.shared.reloadAllTimelines()
    }
    #else
    static func reload() {}
    #endif
}
