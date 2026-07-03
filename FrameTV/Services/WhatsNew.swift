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
                    symbol: "play.rectangle.on.rectangle",
                    title: "Apple TV-style detail screen",
                    detail: "Shows and movies open the same cinematic detail screen everywhere, with a centered hero, a season rail, and a rail of episode cards for each season."
                ),
                ReleaseFeature(
                    symbol: "rectangle.stack",
                    title: "Shows stay together",
                    detail: "Your library and Home rows list each show once instead of a card per episode, with every season and episode stacked under the show."
                ),
                ReleaseFeature(
                    symbol: "arrow.triangle.2.circlepath",
                    title: "Automatic stream failover",
                    detail: "Dead or expired links are detected and skipped automatically, so playback moves on to the next working stream."
                ),
                ReleaseFeature(
                    symbol: "photo",
                    title: "Sharper artwork",
                    detail: "Posters, backdrops, and episode stills load at higher resolution and keep their correct shape, so nothing looks stretched."
                ),
                ReleaseFeature(
                    symbol: "slider.horizontal.3",
                    title: "Controls that fit your screen",
                    detail: "Player controls are reachable on every device, and screens size themselves to your iPhone or iPad."
                )
            ]
        ),
        ReleaseNote(
            version: "1.2",
            headline: "A new look on every screen, plus watch tracking",
            features: [
                ReleaseFeature(
                    symbol: "paintbrush",
                    title: "Cinematic redesign, your way",
                    detail: "New Home, Library, detail sheet, floating tab bar, and refined buttons and cards everywhere. Every screen has a style picker in Settings, Appearance, so the classic look is one tap away."
                ),
                ReleaseFeature(
                    symbol: "checkmark.circle",
                    title: "Watch tracking",
                    detail: "Mark titles watched or unwatched from the detail page or by long-pressing a poster, with a green checkmark badge on watched artwork."
                ),
                ReleaseFeature(
                    symbol: "puzzlepiece.extension",
                    title: "Smarter addon management",
                    detail: "Group addons into categories, ping them all with one Health check, and export or import your whole addon setup as a file."
                ),
                ReleaseFeature(
                    symbol: "textformat.size",
                    title: "Text size and easier paste",
                    detail: "The whole app now follows your system text size, with an in-app size slider, and link fields have one-tap Paste."
                )
            ]
        ),
        ReleaseNote(
            version: "3-old",
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

    /// A generic note used when there is no hand-written entry for the current
    /// version. This guarantees the What's New screen always has something to show
    /// after an update, even when a specific changelog wasn't authored for it.
    static func fallbackNote(version: String) -> ReleaseNote {
        ReleaseNote(
            version: version,
            headline: "Improvements and fixes",
            features: [
                ReleaseFeature(
                    symbol: "sparkles",
                    title: "Refinements under the hood",
                    detail: "This build includes stability fixes and small improvements across the app."
                )
            ]
        )
    }

    /// The note to present for a version: the authored one if it exists, otherwise
    /// the newest authored note (so real release notes still show after version
    /// bumps between authored entries), otherwise the generic fallback.
    static func resolvedNote(for version: String) -> ReleaseNote {
        note(for: version) ?? latest ?? fallbackNote(version: version)
    }
}

// MARK: - Version / build tracking

@MainActor
final class WhatsNewTracker: ObservableObject {
    static let shared = WhatsNewTracker()

    // Keyed off the build number so a new What's New is offered on every increment,
    // since version and build now move together on each build or fix.
    private let key = "whatsNew.lastSeenBuild"

    /// The app's current marketing version from the bundle (CFBundleShortVersionString).
    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1"
    }

    /// The app's current build number from the bundle (CFBundleVersion).
    var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    /// The release note to show for the current version (authored or fallback).
    var currentNote: ReleaseNote {
        WhatsNew.resolvedNote(for: currentVersion)
    }

    /// Whether a What's New screen should be shown: the user hasn't seen this build yet.
    func shouldShow() -> Bool {
        let seen = UserDefaults.standard.string(forKey: key)
        return seen != currentBuild
    }

    /// Marks the current build as seen so the screen isn't shown again until the next one.
    func markSeen() {
        UserDefaults.standard.set(currentBuild, forKey: key)
    }
}
