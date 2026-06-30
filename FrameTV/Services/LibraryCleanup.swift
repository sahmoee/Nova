//
//  LibraryCleanup.swift
//  FrameTV
//
//  Detects items the user started but seems to have abandoned: there's a resume point
//  (more than a token amount watched, not finished) and it hasn't been touched in a
//  while. Surfaces them so the user can keep, clear progress, archive (hide), or
//  restart — without deleting anything automatically.
//

import Foundation

enum LibraryCleanup {
    /// Items considered "abandoned": have a resume point and weren't played within
    /// `staleDays`. Sorted most-stale first.
    static func abandoned(in items: [MediaItem], staleDays: Int = 30) -> [MediaItem] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -staleDays, to: Date()) ?? .distantPast
        return items
            .filter { item in
                guard item.hasResumePoint, !item.isHidden else { return false }
                // No play date, or played before the cutoff, counts as stale.
                if let last = item.lastPlayedDate { return last < cutoff }
                return true
            }
            .sorted { ($0.lastPlayedDate ?? .distantPast) < ($1.lastPlayedDate ?? .distantPast) }
    }

    /// A human-friendly description of how stale an item is.
    static func staleness(_ item: MediaItem) -> String {
        guard let last = item.lastPlayedDate else { return "Never finished" }
        let days = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
        if days >= 365 { return "Over a year ago" }
        if days >= 60 { return "\(days / 30) months ago" }
        if days >= 14 { return "\(days / 7) weeks ago" }
        return "\(max(days, 1)) days ago"
    }
}
