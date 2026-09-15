import Foundation

@main
struct WatchNightChecks {
    static var count = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) { precondition(condition(), message); count += 1 }
    static func rejects(_ message: String, _ operation: () throws -> Void) {
        do { try operation(); fatalError("Expected rejection: \(message)") } catch { count += 1 }
    }
    static func title(_ character: String, name: String = "Title", portableID: String? = nil, duration: Double? = 5400, remaining: Double? = nil, watched: Bool = false) -> WatchNightTitle {
        WatchNightTitle(id: String(repeating: character, count: 64), portableID: portableID, title: name, year: 2026, duration: duration, remaining: remaining, source: "Jellyfin", isWatched: watched, isSeries: false, isFavorite: false)
    }
    static func main() throws {
        let a = title("a", name: "First", portableID: "imdb:tt1", duration: 7800, remaining: 1800)
        let b = title("b", name: "Second", portableID: "imdb:tt2", duration: 5400)
        let unknown = title("c", duration: nil)
        let watched = title("d", duration: 1800, watched: true)
        check(WatchNightLogic.fitting([a,b,unknown], minutes: 120, useRemaining: false, unwatchedOnly: false).map(\.id) == [b.id], "Full runtime budget")
        check(WatchNightLogic.fitting([a,b,unknown], minutes: 120, useRemaining: true, unwatchedOnly: false).map(\.id) == [b.id,a.id], "Closest fit uses remaining time")
        check(WatchNightLogic.fitting([watched], minutes: 120, useRemaining: true, unwatchedOnly: true).isEmpty, "Unwatched filter")
        check(WatchNightLogic.fitting([a], minutes: 0, useRemaining: true, unwatchedOnly: false).isEmpty, "Invalid budget")
        check(WatchNightLogic.fitting([a,b], minutes: 120, useRemaining: true, unwatchedOnly: false, isCancelled: { true }).isEmpty, "Cancelled fitting stops before sorting")
        check(WatchNightLogic.fitting([title("e", duration: .nan)], minutes: 120, useRemaining: false, unwatchedOnly: false).isEmpty, "NaN runtime")
        check(WatchNightLogic.minutes(.greatestFiniteMagnitude) == "Runtime unknown", "No integer overflow")
        check(WatchNightLogic.minutes(-1) == "Runtime unknown", "Negative runtime")
        check(WatchNightLogic.minutes(61) == "2 min", "Round runtime up for planning")

        var plan = WatchNightPlan(name: "Friday", startsAt: Date(timeIntervalSince1970: 1_800_000_000), availableMinutes: 120, breakMinutes: 10, entries: [a.entry(remaining: true),b.entry(remaining: false)])
        try plan.validate()
        check(plan.knownSeconds == 7800, "Break included between titles")
        check(plan.exceedsBudget, "Budget overrun")
        check(plan.startDate(for: 1) == plan.startsAt.addingTimeInterval(2400), "Second title schedule")
        check(plan.estimatedEnd == plan.startsAt.addingTimeInterval(7800), "Finish estimate")
        plan.entries.append(unknown.entry(remaining: true))
        check(plan.unknownCount == 1 && plan.estimatedEnd == nil, "Unknown time hides exact finish")
        plan.entries.insert(unknown.entry(remaining: true), at: 0)
        check(plan.startDate(for: 1) == nil, "Unknown predecessor hides schedule")
        plan.entries = [a.entry(remaining: true),b.entry(remaining: false)]
        let data = try WatchNightPortablePlan.encode(plan)
        let imported = try WatchNightPortablePlan.decode(data)
        check(imported.id != plan.id && imported.entries[0].id != plan.entries[0].id, "Import creates a separate copy")
        check(imported.entries.map(\.title) == plan.entries.map(\.title), "Round trip keeps lineup")
        check(!String(decoding: data, as: UTF8.self).contains("playbackURL"), "Export has no playback addresses")
        check(!String(decoding: data, as: UTF8.self).contains("notes"), "Export has no private notes")
        rejects("Byte limit") { _ = try WatchNightPortablePlan.decode(Data(repeating: 65, count: WatchNightPortablePlan.maximumBytes + 1)) }
        rejects("Unknown format") { _ = try WatchNightPortablePlan.decode(Data("{}".utf8)) }
        var huge = plan
        huge.entries[0].title = String(repeating: "a" + String(repeating: "\u{0301}", count: 3000), count: 100)
        check(huge.entries[0].title.count == 100, "Fixture uses valid grapheme count")
        rejects("Export byte limit") { _ = try WatchNightPortablePlan.encode(huge) }
        var invalid = plan; invalid.startsAt = Date(timeIntervalSince1970: 1e300)
        rejects("Extreme date") { try invalid.validate() }
        invalid.startsAt = Date(timeIntervalSince1970: -.infinity)
        rejects("Nonfinite date") { try invalid.validate() }
        invalid = plan; invalid.breakMinutes = -1
        rejects("Negative breaks") { try invalid.validate() }
        invalid = plan; invalid.entries[0].titleID = "url:https://host/private?token=redacted"
        rejects("Raw URL identity") { try invalid.validate() }
        invalid = plan; invalid.entries[0].portableID = "addon:https://private"
        rejects("Nonportable ID") { try invalid.validate() }
        invalid = plan; invalid.entries += Array(repeating: a.entry(remaining: false), count: 40)
        rejects("Lineup limit") { try invalid.validate() }
        var state = WatchNightState(plans: [plan,plan])
        rejects("Duplicate plans") { try state.validate() }
        state = WatchNightState(notes: [WatchNightNote(id: a.id, title: a.title, text: "Private", modifiedAt: Date(timeIntervalSince1970: 1e300))])
        rejects("Extreme note date") { try state.validate() }

        var reference = a.entry(remaining: false)
        reference.titleID = String(repeating: "e", count: 64)
        check(WatchNightLogic.matching(reference, in: [a])?.id == a.id, "Portable match across local IDs")
        var conflicting = a; conflicting.id = String(repeating: "f", count: 64); conflicting.portableID = "imdb:tt999"
        check(WatchNightLogic.matching(reference, in: [conflicting]) == nil, "Never replace an explicit ID with a conflicting title match")
        var duplicate = a; duplicate.id = String(repeating: "f", count: 64)
        check(WatchNightLogic.matching(reference, in: [a,duplicate]) == nil, "Ambiguous portable ID")
        reference.portableID = nil
        check(WatchNightLogic.matching(reference, in: [a])?.id == a.id, "Unique title-year fallback without external ID")
        check(WatchNightLogic.matching(reference, in: [a,duplicate]) == nil, "Ambiguous title-year fallback")
        reference.titleID = a.id; reference.portableID = "imdb:tt999"
        check(WatchNightLogic.matching(reference, in: [a]) == nil, "Reject conflicting explicit IDs even for a local key")
        print("PASS: \(count) Watch Night core checks")
    }
}
