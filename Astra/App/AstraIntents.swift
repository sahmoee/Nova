//
//  AstraIntents.swift
//  Astra
//
//  Siri Shortcuts / App Intents. These let the user say things like "Continue watching
//  on Astra" or "Open Astra Library", and add Astra actions to the Shortcuts app.
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

    /// Store a astra:// URL string to be routed on next activation.
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

/// "Continue watching on Astra" — opens the app to the Library / Continue Watching.
struct ContinueWatchingIntent: AppIntent {
    static let title: LocalizedStringResource = "Continue Watching"
    static let description = IntentDescription("Open Astra to your Continue Watching list.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingRoute.set("astra://continue")
        return .result()
    }
}

/// "Open Astra Library" — jumps straight to the Library tab.
struct OpenLibraryIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Library"
    static let description = IntentDescription("Open Astra to your library.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingRoute.set("astra://library")
        return .result()
    }
}

/// "Discover on Astra" — opens the Discover tab.
struct OpenDiscoverIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Discover"
    static let description = IntentDescription("Open Astra to Discover.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingRoute.set("astra://discover")
        return .result()
    }
}

/// "Ask Astra AI" — opens the AI tab to build a shelf or search by vibe.
struct OpenAIIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Astra AI"
    static let description = IntentDescription("Open Astra's AI tab to build shelves and playlists.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingRoute.set("astra://ai")
        return .result()
    }
}

// MARK: - Shortcuts provider

/// Registers the above as ready-to-use Shortcuts with spoken phrases. The phrases must
/// include the app name token so Siri can disambiguate.
struct AstraShortcuts: AppShortcutsProvider {
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
