//
//  FrameTVIntents.swift
//  FrameTV
//
//  Siri Shortcuts / App Intents. These let the user say things like "Continue watching
//  on FrameTV" or "Open FrameTV Library", and add FrameTV actions to the Shortcuts app.
//
//  Each intent records a pending route (via PendingRoute) and opens the app; the app
//  drains the route when it becomes active and navigates using the same deep-link
//  router. This keeps intents (which run out-of-process) decoupled from the UI.
//
//  Available on iOS and tvOS (App Intents exists on both at our deployment target).
//

import AppIntents
import Foundation

/// A small shared channel for "where should the app go when it next becomes active."
/// Written by intents, read by the app on activation. Uses UserDefaults so it works
/// across the intent process and the app process.
enum PendingRoute {
    private static let key = "pendingDeepLinkRoute"

    /// Store a frametv:// URL string to be routed on next activation.
    static func set(_ urlString: String) {
        UserDefaults.standard.set(urlString, forKey: key)
    }

    /// Read and clear the pending route, if any.
    static func take() -> URL? {
        guard let s = UserDefaults.standard.string(forKey: key) else { return nil }
        UserDefaults.standard.removeObject(forKey: key)
        return URL(string: s)
    }
}

// MARK: - Intents

/// "Continue watching on FrameTV" — opens the app to the Library / Continue Watching.
struct ContinueWatchingIntent: AppIntent {
    static var title: LocalizedStringResource = "Continue Watching"
    static var description = IntentDescription("Open FrameTV to your Continue Watching list.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingRoute.set("frametv://continue")
        return .result()
    }
}

/// "Open FrameTV Library" — jumps straight to the Library tab.
struct OpenLibraryIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Library"
    static var description = IntentDescription("Open FrameTV to your library.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingRoute.set("frametv://library")
        return .result()
    }
}

/// "Discover on FrameTV" — opens the Discover tab.
struct OpenDiscoverIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Discover"
    static var description = IntentDescription("Open FrameTV to Discover.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingRoute.set("frametv://discover")
        return .result()
    }
}

/// "Ask FrameTV AI" — opens the AI tab to build a shelf or search by vibe.
struct OpenAIIntent: AppIntent {
    static var title: LocalizedStringResource = "Open FrameTV AI"
    static var description = IntentDescription("Open FrameTV's AI tab to build shelves and playlists.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingRoute.set("frametv://ai")
        return .result()
    }
}

// MARK: - Shortcuts provider

/// Registers the above as ready-to-use Shortcuts with spoken phrases. The phrases must
/// include the app name token so Siri can disambiguate.
struct FrameTVShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ContinueWatchingIntent(),
            phrases: [
                "Continue watching on \(.applicationName)",
                "Resume \(.applicationName)"
            ],
            shortTitle: "Continue Watching",
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: OpenLibraryIntent(),
            phrases: [
                "Open \(.applicationName) Library",
                "Show my \(.applicationName) library"
            ],
            shortTitle: "Open Library",
            systemImageName: "rectangle.stack"
        )
        AppShortcut(
            intent: OpenDiscoverIntent(),
            phrases: [
                "Discover on \(.applicationName)",
                "Browse \(.applicationName)"
            ],
            shortTitle: "Open Discover",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: OpenAIIntent(),
            phrases: [
                "Ask \(.applicationName) AI",
                "Open \(.applicationName) AI"
            ],
            shortTitle: "Open AI",
            systemImageName: "sparkles"
        )
    }
}
