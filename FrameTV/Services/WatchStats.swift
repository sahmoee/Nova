//
//  WatchStats.swift
//  FrameTV
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
    var totalHoursWatched: Double      // estimated, from saved positions
    var longestTitle: (title: String, minutes: Int)?
    var mostRecentlyPlayed: (title: String, date: Date)?
    var movies: Int
    var shows: Int

    static func compute(from items: [MediaItem]) -> WatchStats {
        let cal = Calendar.current
        let now = Date()
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now

        var watchedThisMonth = 0
        var watchedAllTime = 0
        var inProgress = 0
        var totalSeconds: Double = 0
        var longest: (String, Int)? = nil
        var recent: (String, Date)? = nil
        var movies = 0
        var shows = 0

        for item in items {
            if item.isWatched {
                watchedAllTime += 1
                if let played = item.lastPlayedDate, played >= monthStart { watchedThisMonth += 1 }
            } else if item.hasResumePoint {
                inProgress += 1
            }
            // Estimated watch time: how far into each title the user got.
            totalSeconds += item.lastPlayedPosition

            // Longest title by duration.
            if let dur = item.duration {
                let mins = Int(dur / 60)
                if longest == nil || mins > longest!.1 {
                    longest = (item.seriesTitle ?? item.title, mins)
                }
            }
            // Most recently played.
            if let played = item.lastPlayedDate {
                if recent == nil || played > recent!.1 {
                    recent = (item.seriesTitle ?? item.title, played)
                }
            }
            let isShow = item.contentID?.type == .series || item.episode != nil
            if isShow { shows += 1 } else { movies += 1 }
        }

        return WatchStats(
            watchedThisMonth: watchedThisMonth,
            watchedAllTime: watchedAllTime,
            inProgress: inProgress,
            totalHoursWatched: totalSeconds / 3600,
            longestTitle: longest.map { (title: $0.0, minutes: $0.1) },
            mostRecentlyPlayed: recent.map { (title: $0.0, date: $0.1) },
            movies: movies,
            shows: shows
        )
    }
}
