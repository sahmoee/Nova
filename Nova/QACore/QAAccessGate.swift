// QAAccessGate.swift
// ─────────────────────────────────────────────────────────────────────────────
// Shared QACore — verbatim from Stocked Build 74.
//
// One unlock lasts ten minutes across every QA screen. The code is "Joo"
// (case-insensitive) — shared across all apps, set here as a constant.
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

@MainActor
@Observable
final class QAAccessGate {
    static let shared = QAAccessGate()

    static let window: TimeInterval = 10 * 60
    private static let code = "Joo"

    private static let unlockedAtKey   = "qa.access.unlockedAt"
    private static let everUnlockedKey = "qa.access.everUnlocked"

    private(set) var unlockedAt: Date?
    /// Sticky — once true it stays true for the life of the install, so a
    /// returning tester sees "your session expired" rather than the first-time
    /// "enter the code to open QA" message.
    private(set) var hasEverUnlocked: Bool

    private init() {
        hasEverUnlocked = UserDefaults.standard.bool(forKey: Self.everUnlockedKey)
        if let ts = UserDefaults.standard.object(forKey: Self.unlockedAtKey) as? Double {
            let date = Date(timeIntervalSince1970: ts)
            if Date().timeIntervalSince(date) < Self.window {
                unlockedAt = date
            }
        }
    }

    var isUnlocked: Bool {
        guard let at = unlockedAt else { return false }
        return Date().timeIntervalSince(at) < Self.window
    }

    var secondsRemaining: TimeInterval {
        guard let at = unlockedAt else { return 0 }
        return max(0, Self.window - Date().timeIntervalSince(at))
    }

    var remainingText: String {
        let s = Int(secondsRemaining)
        let m = s / 60; let sec = s % 60
        return m > 0 ? "\(m)m \(sec)s" : "\(sec)s"
    }

    @discardableResult
    func unlock(with entry: String) -> Bool {
        guard entry.trimmingCharacters(in: .whitespacesAndNewlines)
                   .lowercased() == Self.code.lowercased() else { return false }
        stampUnlocked()
        return true
    }

    /// Extend the window while already unlocked — call from any long-lived QA
    /// screen's `.task` tick so a multi-hour session doesn't expire mid-ticket.
    func refresh() {
        guard isUnlocked else { return }
        stampUnlocked()
    }

    func lock() {
        unlockedAt = nil
        UserDefaults.standard.removeObject(forKey: Self.unlockedAtKey)
    }

    /// Call from a one-second `.task` tick in `QAUnlockGate`. `isUnlocked` is
    /// computed from `Date()`, which `@Observable` cannot track; this turns a
    /// staleness into an observable mutation.
    func expireIfLapsed() {
        if unlockedAt != nil && !isUnlocked { lock() }
    }

    private func stampUnlocked() {
        let now = Date()
        unlockedAt = now
        hasEverUnlocked = true
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Self.unlockedAtKey)
        UserDefaults.standard.set(true, forKey: Self.everUnlockedKey)
    }
}
