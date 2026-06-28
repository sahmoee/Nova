//
//  WhatsNew.swift
//  FrameTV
//
//  Drives the "What's New" screen. To keep it always current, add a new
//  ReleaseNote to the top of `WhatsNew.releases` whenever you ship a version.
//  The screen is shown automatically the first time the app runs a version newer
//  than the last one the user saw, and is always reachable from Settings.
//
//  KEEP THIS UPDATED: the entry whose `version` matches the app's marketing
//  version is shown on launch after an update.
//

import Foundation

struct ReleaseFeature: Identifiable {
    let id = UUID()
    let symbol: String
    let title: String
    let detail: String
}

struct ReleaseNote: Identifiable {
    let id = UUID()
    let version: String          // marketing version, e.g. "2"
    let headline: String
    let features: [ReleaseFeature]
}

enum WhatsNew {

    /// The changelog. Newest version first. Add a new entry on every release.
    static let releases: [ReleaseNote] = [
        ReleaseNote(
            version: "3",
            headline: "A cinematic redesign and smarter sources",
            features: [
                ReleaseFeature(
                    symbol: "paintpalette",
                    title: "Apple TV style redesign",
                    detail: "A dark, cinematic look with a featured banner and an accent color drawn from the artwork you're viewing."
                ),
                ReleaseFeature(
                    symbol: "checkmark.seal",
                    title: "Source health badges",
                    detail: "Streams show Cached, Fast, 4K, HDR, Dolby Vision, Dolby Atmos, Low Seed Risk, and source at a glance."
                ),
                ReleaseFeature(
                    symbol: "wand.and.stars",
                    title: "Smart source ranking",
                    detail: "The best stream is chosen across resolution, HDR, audio, codec, seeders, and file size, not just quality."
                ),
                ReleaseFeature(
                    symbol: "line.3.horizontal.decrease.circle",
                    title: "Movies & Shows filter",
                    detail: "Filter your Library by movies or shows on top of Recently Added, Favorites, and Continue Watching."
                ),
                ReleaseFeature(
                    symbol: "sparkle.magnifyingglass",
                    title: "A fresh Discover every time",
                    detail: "Discover reshuffles its rows on each visit and shows a different selection than Home."
                )
            ]
        ),
        ReleaseNote(
            version: "2",
            headline: "Network drives, backup, and a smoother player",
            features: [
                ReleaseFeature(
                    symbol: "externaldrive.connected.to.line.below",
                    title: "Stream from SMB drives",
                    detail: "Play video straight from your network shares. Nothing is copied to the device."
                ),
                ReleaseFeature(
                    symbol: "icloud.and.arrow.up",
                    title: "iCloud backup & restore",
                    detail: "Save your sources, settings, and logins to iCloud and restore them on another device."
                ),
                ReleaseFeature(
                    symbol: "play.rectangle.on.rectangle",
                    title: "Up-next & auto-play",
                    detail: "A countdown card cues the next episode, and controls now get out of the way while you watch."
                ),
                ReleaseFeature(
                    symbol: "checkmark.circle",
                    title: "Watched markers & resume",
                    detail: "Episodes show watched and in-progress states, with a quick jump to the next unwatched one."
                ),
                ReleaseFeature(
                    symbol: "key",
                    title: "Quick service sign-in",
                    detail: "Open the right page to get an API key or sign in for each connected service."
                )
            ]
        )
    ]

    /// The release note matching a given marketing version, if any.
    static func note(for version: String) -> ReleaseNote? {
        releases.first { $0.version == version }
    }

    /// The newest release note.
    static var latest: ReleaseNote? { releases.first }
}

// MARK: - Seen-version tracking

@MainActor
final class WhatsNewTracker: ObservableObject {
    static let shared = WhatsNewTracker()

    private let key = "whatsNew.lastSeenVersion"

    /// The app's current marketing version from the bundle.
    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1"
    }

    /// Whether a What's New screen should be shown for the current version: there
    /// is a matching note and the user hasn't seen this version yet.
    func shouldShow() -> Bool {
        let seen = UserDefaults.standard.string(forKey: key)
        guard seen != currentVersion else { return false }
        return WhatsNew.note(for: currentVersion) != nil
    }

    /// Marks the current version as seen so the screen isn't shown again.
    func markSeen() {
        UserDefaults.standard.set(currentVersion, forKey: key)
    }
}
