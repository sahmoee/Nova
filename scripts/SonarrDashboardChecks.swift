import Foundation

/// Native fixtures only. No user settings, Keychain, or personal server requests.
@main enum SonarrDashboardChecks {
    static func main() throws {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) { precondition(condition(), name); count += 1 }
        let base = SonarrDashboardPolicy.serverURL(" https://jarvis.example/sonarr/ \n")!
        check(base.absoluteString == "https://jarvis.example/sonarr", "Retain leading reverse proxy slash")
        check(base.appendingPathComponent("api/v3/series").path == "/sonarr/api/v3/series", "Append endpoint inside proxy path")
        for invalid in ["http://", "file:///tmp/server", "ftp://example.com", "https://key@example.com", "https://user:secret@example.com", "https://example.com/?apikey=secret", "https://example.com/#fragment", "example.com"] {
            check(SonarrDashboardPolicy.serverURL(invalid) == nil, "Reject invalid or credential-bearing URL")
        }
        check(SonarrDashboardPolicy.serverURL("http://192.168.1.2:8989") != nil, "Allow private HTTP server")
        check(SonarrDashboardPolicy.serverURL("https://[::1]:8989/sonarr") != nil, "Allow IPv6 server")
        check(SonarrDashboardPolicy.missing(expected: nil, files: 3) == nil, "Unknown expected count")
        check(SonarrDashboardPolicy.missing(expected: 8, files: nil) == nil, "Unknown files")
        check(SonarrDashboardPolicy.missing(expected: 8, files: 3) == 5, "Missing estimate")
        check(SonarrDashboardPolicy.missing(expected: 8, files: 12) == 0, "Unmonitored extras don't cause negative missing")
        check(SonarrDashboardPolicy.missing(expected: -1, files: 0) == nil, "Invalid stats unavailable")
        check(SonarrDashboardPolicy.progress(size: 100, remaining: 75) == 0.25, "Byte progress")
        for pair: (Double?, Double?) in [(nil, 3), (0, 0), (100, nil), (100, -1), (100, 101), (.infinity, 3), (100, .nan)] {
            check(SonarrDashboardPolicy.progress(size: pair.0, remaining: pair.1) == nil, "Unknown or invalid progress is not zero")
        }
        let seriesJSON = #"[{"id":1,"title":"Café","monitored":true,"statistics":{"episodeCount":8,"episodeFileCount":3,"totalEpisodeCount":12,"sizeOnDisk":2000}},{"id":2,"title":"Alpha","monitored":true,"statistics":{"episodeCount":4,"episodeFileCount":4}},{"id":3,"title":"Beta","monitored":false},{"id":4,"title":"Alpha","monitored":false,"statistics":{"episodeCount":0,"episodeFileCount":0}}]"#
        let series = try SonarrDashboardPolicy.decoder().decode([SonarrSeries].self, from: Data(seriesJSON.utf8))
        check(SonarrDashboardPolicy.filterSeries(series, query: " cafe ", filter: .all, sort: .title).map(\.id) == [1], "Accent and whitespace query")
        check(SonarrDashboardPolicy.filterSeries(series, query: "", filter: .monitored, sort: .title).map(\.id) == [2, 1], "Monitored filter")
        check(SonarrDashboardPolicy.filterSeries(series, query: "", filter: .missing, sort: .title).map(\.id) == [1], "Missing filter")
        check(SonarrDashboardPolicy.filterSeries(series, query: "", filter: .complete, sort: .title).map(\.id) == [2], "Zero/unknown episodes not complete")
        check(SonarrDashboardPolicy.filterSeries(series, query: "", filter: .all, sort: .title).map(\.id) == [2, 4, 3, 1], "Stable title ties")
        check(SonarrDashboardPolicy.filterSeries(series, query: "", filter: .all, sort: .missing).first?.id == 1, "Largest missing first")
        check(SonarrDashboardPolicy.filterSeries(series, query: "", filter: .all, sort: .files).first?.id == 2, "Most files first")
        let queueJSON = #"[{"id":1,"title":"Example","status":"downloading","trackedDownloadStatus":"warning","size":1000,"sizeleft":250,"timeleft":"00:01:00","estimatedCompletionTime":"2026-09-14T18:00:00.123Z","downloadClient":"Example client","statusMessages":[{"title":"Import warning","messages":["Waiting"]}]},{"id":2,"size":0,"sizeleft":0,"estimatedCompletionTime":"2026-09-14T18:00:00Z"},{"id":3,"trackedDownloadStatus":"error"}]"#
        let queue = try SonarrDashboardPolicy.decoder().decode([SonarrQueueItem].self, from: Data(queueJSON.utf8))
        check(queue[0].progress == 0.75 && queue[0].timeleft == "00:01:00", "Actual Sonarr sizeleft/timeleft keys")
        check(queue[0].hasWarning && queue[2].hasWarning, "Warning and error are surfaced")
        check(queue[1].progress == nil && queue[1].title == nil, "Partial queue record supported")
        check(queue[0].estimatedCompletionTime != nil && queue[1].estimatedCompletionTime != nil, "Fractional and whole ISO timestamps")
        check(queue[0].statusMessages?.first?.messages == ["Waiting"], "Queue diagnostics decoded")
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let today = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!
        let start = calendar.startOfDay(for: today)
        func episode(_ id: Int, date: Date?, monitored: Bool = true, file: Bool = false) -> SonarrEpisode {
            SonarrEpisode(id: id, seriesId: 1, seasonNumber: 1, episodeNumber: id, title: "Episode", airDateUtc: date, hasFile: file, monitored: monitored)
        }
        let episodes = [episode(1, date: start), episode(2, date: start.addingTimeInterval(-1)), episode(3, date: calendar.date(byAdding: .day, value: 1, to: start)), episode(4, date: start, monitored: false, file: true), episode(5, date: nil)]
        check(SonarrDashboardPolicy.filterEpisodes(episodes, days: 1, monitoring: .all, files: .all, now: today, calendar: calendar).map(\.id) == [1, 4], "Local DST calendar today and stable order")
        check(SonarrDashboardPolicy.filterEpisodes(episodes, days: 7, monitoring: .monitored, files: .missing, now: today, calendar: calendar).map(\.id) == [1, 3], "Calendar combined filters")
        check(SonarrDashboardPolicy.filterEpisodes(episodes, days: 30, monitoring: .unmonitored, files: .available, now: today, calendar: calendar).map(\.id) == [4], "Unmonitored available filter")
        print("Sonarr dashboard checks passed: \(count)")
    }
}
