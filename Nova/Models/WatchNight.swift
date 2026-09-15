import Foundation

/// Local planning metadata. No playback addresses, credentials, or private notes travel in a plan.
struct WatchNightEntry: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var titleID: String
    var portableID: String?
    var title: String
    var year: Int?
    var estimatedSeconds: Double?
    var usesRemainingTime = false
}

struct WatchNightPlan: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var startsAt = Date()
    var availableMinutes = 180
    var breakMinutes = 5
    var entries: [WatchNightEntry] = []

    var knownSeconds: Double {
        entries.compactMap(\.estimatedSeconds).reduce(0, +) + Double(max(0, entries.count - 1) * breakMinutes * 60)
    }
    var unknownCount: Int { entries.filter { $0.estimatedSeconds == nil }.count }
    var estimatedEnd: Date? { unknownCount == 0 ? startsAt.addingTimeInterval(knownSeconds) : nil }
    var exceedsBudget: Bool { knownSeconds > Double(availableMinutes * 60) }
    func startDate(for index: Int) -> Date? {
        guard entries.indices.contains(index) else { return nil }
        let previous = entries.prefix(index)
        guard previous.allSatisfy({ $0.estimatedSeconds != nil }) else { return nil }
        return startsAt.addingTimeInterval(previous.compactMap(\.estimatedSeconds).reduce(0, +) + Double(index * breakMinutes * 60))
    }
    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 100,
              Self.validDate(startsAt), (15...1440).contains(availableMinutes),
              (0...60).contains(breakMinutes), entries.count <= 40,
              Set(entries.map(\.id)).count == entries.count else { throw WatchNightError.invalid("Use a name of 1–100 characters, up to 40 titles, a 15-minute to 24-hour budget, and breaks of up to 60 minutes.") }
        for entry in entries {
            guard Self.validTitleID(entry.titleID), entry.portableID.map(Self.validPortableID) ?? true,
                  !entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, entry.title.count <= 300,
                  entry.year.map({ (1800...2300).contains($0) }) ?? true,
                  entry.estimatedSeconds.map({ $0.isFinite && $0 > 0 && $0 <= 86400 }) ?? true else {
                throw WatchNightError.invalid("A title in this plan has invalid identity, text, year, or runtime.")
            }
        }
    }
    static func validDate(_ date: Date) -> Bool {
        (-2_208_988_800...7_258_118_400).contains(date.timeIntervalSince1970)
    }
    static func validTitleID(_ id: String) -> Bool { id.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil }
    static func validPortableID(_ id: String) -> Bool {
        id.range(of: "^(imdb:tt[0-9]{1,12}|tmdb:(movie|series):[0-9]{1,12})(\\|s[0-9]{1,5}e[0-9]{1,5})?$", options: .regularExpression) != nil
    }
}

struct WatchNightNote: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var text: String
    var containsSpoilers = true
    var modifiedAt = Date()
}

struct WatchNightState: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var plans: [WatchNightPlan] = []
    var notes: [WatchNightNote] = []
    func validate() throws {
        guard schemaVersion == 1, plans.count <= 30, notes.count <= 300,
              Set(plans.map(\.id)).count == plans.count, Set(notes.map(\.id)).count == notes.count else {
            throw WatchNightError.invalid("Watch Night supports 30 plans and 300 private notes. This file may be from a newer Nova version.")
        }
        try plans.forEach { try $0.validate() }
        for note in notes {
            guard WatchNightPlan.validTitleID(note.id), !note.title.isEmpty, note.title.count <= 300,
                  !note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, note.text.count <= 4000,
                  WatchNightPlan.validDate(note.modifiedAt) else { throw WatchNightError.invalid("A private note has invalid text or identity. Notes can contain up to 4,000 characters.") }
        }
    }
}

struct WatchNightPortablePlan: Codable, Sendable {
    var format = "nova-watch-night"
    var version = 1
    var plan: WatchNightPlan
    static let maximumBytes = 512 * 1024
    static func decode(_ data: Data) throws -> WatchNightPlan {
        guard data.count <= maximumBytes else { throw WatchNightError.invalid("Choose a Watch Night JSON file smaller than 512 KB.") }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.format == "nova-watch-night", value.version == 1 else { throw WatchNightError.invalid("This is not a supported Nova Watch Night plan.") }
        try value.plan.validate()
        var copy = value.plan; copy.id = UUID()
        copy.entries = copy.entries.map { entry in var copy = entry; copy.id = UUID(); return copy }
        return copy
    }
    static func encode(_ plan: WatchNightPlan) throws -> Data {
        try plan.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Self(plan: plan))
        guard data.count <= maximumBytes else { throw WatchNightError.invalid("This plan exceeds the 512 KB portable limit. Shorten its title text before exporting.") }
        return data
    }
}

/// A small, credential-free projection of library metadata for local comparisons and search.
struct WatchNightTitle: Hashable, Identifiable, Sendable {
    var id: String
    var portableID: String?
    var title: String
    var year: Int?
    var duration: Double?
    var remaining: Double?
    var source: String
    var isWatched: Bool
    var isSeries: Bool
    var isFavorite: Bool
    var posterURL: URL?
    func entry(remaining useRemaining: Bool) -> WatchNightEntry {
        WatchNightEntry(titleID: id, portableID: portableID, title: title, year: year,
                        estimatedSeconds: useRemaining ? remaining ?? duration : duration,
                        usesRemainingTime: useRemaining && remaining != nil)
    }
}

enum WatchNightLogic {
    static func matching(_ entry: WatchNightEntry, in titles: [WatchNightTitle]) -> WatchNightTitle? {
        if let exact = titles.first(where: { $0.id == entry.titleID }) {
            if let provided = entry.portableID, let known = exact.portableID, provided != known { return nil }
            return exact
        }
        if let portableID = entry.portableID {
            let matches = titles.filter { $0.portableID == portableID }
            return matches.count == 1 ? matches[0] : nil
        }
        // Do not guess across remakes or multiple versions with the same name.
        let matches = titles.filter { $0.title.caseInsensitiveCompare(entry.title) == .orderedSame && $0.year == entry.year }
        return matches.count == 1 ? matches[0] : nil
    }
    static func fitting(_ titles: [WatchNightTitle], minutes: Int, useRemaining: Bool, unwatchedOnly: Bool,
                        isCancelled: () -> Bool = { false }) -> [WatchNightTitle] {
        guard (1...1440).contains(minutes) else { return [] }
        let available = Double(minutes * 60)
        var matches: [WatchNightTitle] = []
        for title in titles {
            if isCancelled() { return [] }
            guard !unwatchedOnly || !title.isWatched,
                  let seconds = useRemaining ? title.remaining ?? title.duration : title.duration else { continue }
            if seconds.isFinite && seconds > 0 && seconds <= available { matches.append(title) }
        }
        if isCancelled() { return [] }
        return matches.sorted { first, second in
            let a = (useRemaining ? first.remaining ?? first.duration : first.duration) ?? 0
            let b = (useRemaining ? second.remaining ?? second.duration : second.duration) ?? 0
            if a != b { return a > b }
            if first.title != second.title { return first.title.localizedStandardCompare(second.title) == .orderedAscending }
            return first.id < second.id
        }
    }
    static func minutes(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0, seconds <= 40 * 86400 + 40 * 3600 else { return "Runtime unknown" }
        return "\(Int(ceil(seconds / 60))) min"
    }
}

enum WatchNightError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let message): message } }
}
