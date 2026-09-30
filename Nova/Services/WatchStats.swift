//
//  WatchStats.swift
//  Nova
//
//  Personal watch statistics computed from the library. Uses what library items
//  actually record (play dates, positions, durations, watched state). Genre stats are
//  intentionally omitted because library items don't carry genre data — only catalog
//  items do — so reporting a "most-watched genre" here would be guesswork.
//

import Foundation

struct WatchStats {
    var watchedThisMonth: Int
    var watchedAllTime: Int
    var inProgress: Int
    var totalHoursWatched: Double      // estimated, from saved positions and completed titles
    var longestTitle: (title: String, minutes: Int)?
    var mostRecentlyPlayed: (title: String, date: Date)?
    var movies: Int
    /// Distinct series (an episode-by-episode library counts each show once).
    var shows: Int
    /// Titles played in the last 7 days.
    var playedThisWeek: Int
    /// Consecutive days, ending today or yesterday, with at least one title played.
    var currentStreak: Int
    /// The longest run of consecutive viewing days in the library's history.
    var bestStreak: Int
    /// Titles played per day for the last seven days, oldest first.
    var lastSevenDays: [(day: Date, count: Int)]
    /// Shows with the most episodes watched, most first (up to three).
    var topShows: [(title: String, episodes: Int)]

    /// Sentinel duration markWatched writes when a title's real length is unknown.
    private static let unknownDurationSentinel: TimeInterval = 100

    static func compute(from items: [MediaItem], now: Date = Date(), calendar: Calendar = .current) -> WatchStats {
        let cal = calendar
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let today = cal.startOfDay(for: now)
        let weekStart = cal.date(byAdding: .day, value: -6, to: today) ?? today

        var watchedThisMonth = 0
        var watchedAllTime = 0
        var inProgress = 0
        var totalSeconds: Double = 0
        var longest: (String, Int)? = nil
        var recent: (String, Date)? = nil
        var movies = 0
        var seriesNames = Set<String>()
        var playedThisWeek = 0
        var playedDays = Set<Date>()
        var episodesBySeries: [String: (title: String, count: Int)] = [:]

        for item in items where item.sourceType != .liveTV {
            let watched = item.isWatched
            if watched {
                watchedAllTime += 1
                if let played = item.lastPlayedDate, played >= monthStart { watchedThisMonth += 1 }
            } else if item.hasResumePoint {
                inProgress += 1
            }
            // Completed titles reset their saved position to 0, so they contribute their
            // full (known) length; in-progress titles contribute how far the viewer got.
            if watched, let duration = item.duration, duration != unknownDurationSentinel {
                totalSeconds += duration
            } else {
                totalSeconds += item.lastPlayedPosition
            }

            if let dur = item.duration, dur != unknownDurationSentinel {
                let mins = Int(dur / 60)
                if longest.map({ mins > $0.1 }) ?? true {
                    longest = (item.seriesTitle ?? item.title, mins)
                }
            }
            if let played = item.lastPlayedDate {
                if recent.map({ played > $0.1 }) ?? true {
                    recent = (item.seriesTitle ?? item.title, played)
                }
                let day = cal.startOfDay(for: played)
                playedDays.insert(day)
                if day >= weekStart && day <= today { playedThisWeek += 1 }
            }
            if item.isSeries {
                let name = (item.seriesTitle ?? item.title).trimmingCharacters(in: .whitespacesAndNewlines)
                let key = name.lowercased()
                seriesNames.insert(key)
                if watched, item.episode != nil {
                    episodesBySeries[key, default: (name, 0)].count += 1
                }
            } else {
                movies += 1
            }
        }

        let sevenDays: [(day: Date, count: Int)] = (0..<7).reversed().compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let count = items.filter { item in
                item.sourceType != .liveTV && item.lastPlayedDate.map { cal.isDate($0, inSameDayAs: day) } == true
            }.count
            return (day, count)
        }

        return WatchStats(
            watchedThisMonth: watchedThisMonth,
            watchedAllTime: watchedAllTime,
            inProgress: inProgress,
            totalHoursWatched: totalSeconds / 3600,
            longestTitle: longest.map { (title: $0.0, minutes: $0.1) },
            mostRecentlyPlayed: recent.map { (title: $0.0, date: $0.1) },
            movies: movies,
            shows: seriesNames.count,
            playedThisWeek: playedThisWeek,
            currentStreak: streak(endingAt: today, days: playedDays, calendar: cal),
            bestStreak: longestStreak(in: playedDays, calendar: cal),
            lastSevenDays: sevenDays,
            topShows: episodesBySeries.values
                .sorted { $0.count == $1.count ? $0.title < $1.title : $0.count > $1.count }
                .prefix(3).map { (title: $0.title, episodes: $0.count) }
        )
    }

    /// A streak still counts if today has no viewing yet but yesterday did.
    static func streak(endingAt today: Date, days: Set<Date>, calendar: Calendar) -> Int {
        var cursor = today
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today), days.contains(yesterday) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    static func longestStreak(in days: Set<Date>, calendar: Calendar) -> Int {
        var best = 0
        for day in days {
            // Only start counting at the first day of a run.
            if let previous = calendar.date(byAdding: .day, value: -1, to: day), days.contains(previous) { continue }
            var length = 0
            var cursor = day
            while days.contains(cursor) {
                length += 1
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
            best = max(best, length)
        }
        return best
    }
}
