//
//  PlayerCore.swift
//  Astra
//
//  Shared surface for the two player models (AVPlayer-backed PlayerModel and
//  VLCPlayerModel). Both expose identical progress state; the derived values —
//  fraction complete, time remaining, formatted labels — previously lived in each
//  model. They now come from one protocol extension, so overlays and future
//  players compute progress identically.
//

import Foundation

@MainActor
protocol PlayerProgressCore: AnyObject {
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    var isBuffering: Bool { get }
    var didFinish: Bool { get }
}

@MainActor
extension PlayerProgressCore {
    /// Fraction of the item played, clamped to 0...1. Zero when duration is unknown.
    var progressFraction: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    /// Seconds left, never negative.
    var remainingTime: TimeInterval {
        max(duration - currentTime, 0)
    }

    /// Compact elapsed label like "1:23:45" or "23:45".
    var elapsedLabel: String { Self.format(currentTime) }

    /// Compact remaining label like "-23:45".
    var remainingLabel: String { "-" + Self.format(remainingTime) }

    private static func format(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let s = Int(t.rounded())
        let hours = s / 3600, minutes = (s % 3600) / 60, seconds = s % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

extension PlayerModel: PlayerProgressCore {}
extension VLCPlayerModel: PlayerProgressCore {}
