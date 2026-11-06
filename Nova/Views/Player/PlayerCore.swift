//
//  PlayerCore.swift
//  Nova
//
//  Shared surface for the two player models (AVPlayer-backed PlayerModel and
//  VLCPlayerModel). Both expose identical progress state; the derived values —
//  fraction complete, time remaining, formatted labels — previously lived in each
//  model. They now come from one protocol extension, so overlays and future
//  players compute progress identically.
//

import Foundation
import SwiftUI

struct ResumeProgressSummary: View {
    let position: TimeInterval
    let duration: TimeInterval?

    var body: some View {
        if let duration, duration.isFinite, duration > 0, position.isFinite {
            let fraction = min(max(position / duration, 0), 1)
            let minutesLeft = max(1, Int(((duration - position) / 60).rounded(.up)))
            VStack(spacing: 6) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.2))
                        Capsule().fill(.white).frame(width: max(4, proxy.size.width * fraction))
                    }
                }
                .frame(width: 240, height: 4)
                Text("\(Int((fraction * 100).rounded()))% watched · \(minutesLeft >= 60 ? "\(minutesLeft / 60)h \(minutesLeft % 60)m" : "\(minutesLeft) min") left")
                    .font(.appFont(15, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
            }
            .accessibilityElement(children: .combine)
        }
    }
}

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
#if !os(macOS)
extension VLCPlayerModel: PlayerProgressCore {}
#endif
