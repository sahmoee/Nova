import Foundation

/// Watch-only projection. Deliberately contains no URLs, paths, accounts, or private notes.
struct NovaWatchTitle: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var subtitle: String
    var planKey: String
    var duration: Double?
    var position: Double
    var favorite: Bool
    var queued: Bool
    var watched: Bool
    var lastPlayed: Date?
    var isSeries: Bool
    var resumeAvailable: Bool
    var progress: Double { guard let duration, duration > 0 else { return 0 }; return min(1, max(0, position / duration)) }
    var hasResume: Bool { resumeAvailable && !watched }
}

struct NovaWatchPlayer: Codable, Equatable, Sendable {
    var sessionID: UUID
    var title: String
    var playing: Bool
    var position: Double
    var duration: Double?
    var volume: Double?
    var canSeek: Bool
    var observedAt: Date
}

struct NovaWatchSnapshot: Codable, Equatable, Sendable {
    var version = 1
    var phoneID: UUID
    var revision: Int64
    var generatedAt: Date
    var totalTitles: Int
    var titles: [NovaWatchTitle]
    var plans: [WatchNightPlan]
    var totalPlans: Int
    var phoneForeground: Bool
    var acceptsEdits = true
    var player: NovaWatchPlayer?
    var phoneMessage: String?
}

enum NovaWatchLibraryScope: String, Codable, Sendable { case all, continueWatching, favorites, queue, history }

enum NovaWatchAction: String, Codable, Sendable {
    case refresh, search, plans, planDetails, setFavorite, setQueued, setWatched
    case createPlan, renamePlan, setPlanItem, deletePlan, setPlanSchedule, removePlanEntry
    case openOnPhone, setPlaying, seek, setVolume
    var isDurable: Bool {
        switch self {
        case .setFavorite, .setQueued, .setWatched, .createPlan, .renamePlan, .setPlanItem, .deletePlan, .setPlanSchedule, .removePlanEntry: true
        default: false
        }
    }
    var isRemote: Bool { [.setPlaying, .seek, .setVolume].contains(self) }
}

struct NovaWatchCommand: Codable, Equatable, Identifiable, Sendable {
    var version = 1
    var id = UUID()
    var watchID: UUID
    var phoneID: UUID
    var sequence: Int64
    var createdAt = Date()
    var action: NovaWatchAction
    var itemID: UUID?
    var planID: UUID?
    var entryID: UUID?
    var playerSessionID: UUID?
    var flag: Bool?
    var value: Double?
    var text: String?
    var date: Date?
    var offset: Int?
    var scope: NovaWatchLibraryScope?

    func validate(now: Date = Date()) throws {
        guard version == 1, sequence > 0, sequence < Int64.max,
              WatchNightPlan.validDate(createdAt), createdAt.timeIntervalSince(now) < 300,
              text.map({ $0.count <= 100 }) ?? true,
              value.map({ $0.isFinite }) ?? true,
              offset.map({ (0...200_000).contains($0) }) ?? true else { throw NovaWatchFailure.invalid }
        if action.isRemote || action == .openOnPhone {
            guard now.timeIntervalSince(createdAt) < 20, createdAt.timeIntervalSince(now) <= 5 else { throw NovaWatchFailure.expired }
        }
        if action.isRemote { guard playerSessionID != nil else { throw NovaWatchFailure.invalid } }
        switch action {
        case .setFavorite, .setQueued, .setWatched: guard itemID != nil, flag != nil else { throw NovaWatchFailure.invalid }
        case .setPlanItem: guard itemID != nil, planID != nil, flag != nil else { throw NovaWatchFailure.invalid }
        case .createPlan, .renamePlan:
            guard planID != nil, let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw NovaWatchFailure.invalid }
        case .removePlanEntry: guard planID != nil, entryID != nil else { throw NovaWatchFailure.invalid }
        case .deletePlan: guard planID != nil else { throw NovaWatchFailure.invalid }
        case .setPlanSchedule:
            guard planID != nil, let date, WatchNightPlan.validDate(date), let value, (15...1440).contains(value) else { throw NovaWatchFailure.invalid }
        case .setPlaying: guard flag != nil else { throw NovaWatchFailure.invalid }
        case .seek: guard let value, (0...2_147_000).contains(value) else { throw NovaWatchFailure.invalid }
        case .setVolume: guard let value, (0...1).contains(value) else { throw NovaWatchFailure.invalid }
        case .openOnPhone: guard itemID != nil else { throw NovaWatchFailure.invalid }
        case .planDetails: guard planID != nil else { throw NovaWatchFailure.invalid }
        case .refresh, .search, .plans: break
        }
    }
}

struct NovaWatchReceipt: Codable, Equatable, Identifiable, Sendable {
    enum Outcome: String, Codable, Sendable { case applied, rejected, interrupted }
    var id: UUID
    var outcome: Outcome
    var message: String
    var createdAt = Date()
    var updatedTitle: NovaWatchTitle?
    var search: [NovaWatchTitle]?
    var searchTotal: Int?
    var query: String?
    var plans: [NovaWatchPlanSummary]?
    var plan: WatchNightPlan?
    var offset: Int?
}

struct NovaWatchEnvelope: Codable, Sendable {
    var version = 1
    var snapshot: NovaWatchSnapshot?
    var receipt: NovaWatchReceipt?
}

enum NovaWatchFailure: LocalizedError {
    case invalid, expired, full, unreadable, disconnected
    var errorDescription: String? {
        switch self {
        case .invalid: "This watch request is not supported. Update Nova on both devices."
        case .expired: "This playback request expired. Open Nova on iPhone and try again."
        case .full: "The watch queue is full. Sync pending changes before adding more."
        case .unreadable: "Nova could not read its watch data. The original file has been kept."
        case .disconnected: "Open Nova on your paired iPhone, then try again."
        }
    }
}

enum NovaWatchCodec {
    static let maximumMessageBytes = 60_000
    static let maximumDiskBytes = 512_000
    static func encode<T: Encodable>(_ value: T, limit: Int = maximumMessageBytes) throws -> Data {
        let data = try JSONEncoder().encode(value)
        guard data.count <= limit else { throw NovaWatchFailure.full }
        return data
    }
    static func decode<T: Decodable>(_ type: T.Type, data: Data, limit: Int = maximumMessageBytes) throws -> T {
        guard data.count <= limit else { throw NovaWatchFailure.invalid }
        return try JSONDecoder().decode(type, from: data)
    }
    static func validate(_ snapshot: NovaWatchSnapshot) throws {
        guard snapshot.version == 1, snapshot.revision >= 0, WatchNightPlan.validDate(snapshot.generatedAt),
              snapshot.totalTitles >= snapshot.titles.count, snapshot.totalPlans >= snapshot.plans.count,
              snapshot.titles.count <= 200, snapshot.plans.count <= 30,
              Set(snapshot.titles.map(\.id)).count == snapshot.titles.count,
              Set(snapshot.plans.map(\.id)).count == snapshot.plans.count else { throw NovaWatchFailure.invalid }
        for title in snapshot.titles { try validate(title) }
        try snapshot.plans.forEach { try $0.validate() }
        if let player = snapshot.player {
            guard player.title.count <= 180, player.position.isFinite, player.position >= 0,
                  player.duration.map({ $0.isFinite && $0 > 0 }) ?? true,
                  player.volume.map({ $0.isFinite && (0...1).contains($0) }) ?? true,
                  WatchNightPlan.validDate(player.observedAt) else { throw NovaWatchFailure.invalid }
        }
    }
    static func validate(_ title: NovaWatchTitle) throws {
        guard WatchNightPlan.validTitleID(title.planKey), title.title.count <= 180, title.subtitle.count <= 100, title.position.isFinite, title.position >= 0,
              title.duration.map({ $0.isFinite && $0 > 0 }) ?? true,
              title.lastPlayed.map(WatchNightPlan.validDate) ?? true else { throw NovaWatchFailure.invalid }
    }
    static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard properties.isRegularFile == true, properties.isSymbolicLink != true,
              (properties.fileSize ?? maximumDiskBytes + 1) <= maximumDiskBytes else { throw NovaWatchFailure.unreadable }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        return try decode(type, data: handle.read(upToCount: maximumDiskBytes + 1) ?? Data(), limit: maximumDiskBytes)
    }
    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encode(value, limit: maximumDiskBytes)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS) || os(watchOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}

struct NovaWatchOutbox: Codable, Sendable {
    var version = 1
    var watchID = UUID()
    var nextSequence: Int64 = 1
    var commands: [NovaWatchCommand] = []
    mutating func make(phoneID: UUID, action: NovaWatchAction) throws -> NovaWatchCommand {
        guard nextSequence > 0, nextSequence < Int64.max, (!action.isDurable || commands.count < 100) else { throw NovaWatchFailure.full }
        defer { nextSequence += 1 }
        return NovaWatchCommand(watchID: watchID, phoneID: phoneID, sequence: nextSequence, action: action)
    }
    func validate() throws {
        guard version == 1, commands.count <= 100, nextSequence > 0,
              Set(commands.map(\.id)).count == commands.count,
              commands.allSatisfy({ $0.watchID == watchID && $0.action.isDurable && $0.sequence < nextSequence }),
              zip(commands, commands.dropFirst()).allSatisfy({ $0.sequence < $1.sequence }) else { throw NovaWatchFailure.unreadable }
        for command in commands { try command.validate() }
    }
}

/// Persist a reservation before mutating phone data. A crash cannot replay a stale
/// request after later edits; an interrupted reservation reports an uncertain result.
struct NovaWatchJournal: Codable, Sendable {
    var version = 1
    var phoneID = UUID()
    var snapshotRevision: Int64 = 0
    var resetWatermark: Double = 0
    var lastSequences: [String: Int64] = [:]
    var receipts: [NovaWatchReceipt] = []
    func previous(_ command: NovaWatchCommand) -> NovaWatchReceipt? {
        if let receipt = receipts.first(where: { $0.id == command.id }) { return receipt }
        if command.sequence <= (lastSequences[command.watchID.uuidString] ?? 0) {
            return NovaWatchReceipt(id: command.id, outcome: .rejected, message: "This older request was already handled. Refresh to see current state.")
        }
        return nil
    }
    mutating func reserve(_ command: NovaWatchCommand) throws {
        guard command.phoneID == phoneID, lastSequences.count < 16 || lastSequences[command.watchID.uuidString] != nil else { throw NovaWatchFailure.invalid }
        lastSequences[command.watchID.uuidString] = command.sequence
        finish(NovaWatchReceipt(id: command.id, outcome: .interrupted, message: "The previous attempt was interrupted. Refresh before making this change again."))
    }
    mutating func finish(_ receipt: NovaWatchReceipt) {
        receipts.removeAll { $0.id == receipt.id }; receipts.append(receipt)
        if receipts.count > 128 { receipts.removeFirst(receipts.count - 128) }
    }
    func validate() throws {
        guard version == 1, snapshotRevision >= 0, resetWatermark.isFinite, resetWatermark >= 0, lastSequences.count <= 16, receipts.count <= 128,
              lastSequences.values.allSatisfy({ $0 > 0 }), Set(receipts.map(\.id)).count == receipts.count else { throw NovaWatchFailure.unreadable }
        try receipts.forEach { try NovaWatchPolicy.validate($0) }
    }
}

struct NovaWatchPlanSummary: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var startsAt: Date
    var count: Int
    init(_ plan: WatchNightPlan) { id = plan.id; name = plan.name; startsAt = plan.startsAt; count = plan.entries.count }
}

/// Pure gates are shared by the watch UI, cache receiver, and regression fixtures.
enum NovaWatchPolicy {
    enum SnapshotDecision: Equatable { case replace, advance, ignore }
    static func decision(incoming: NovaWatchSnapshot, current: NovaWatchSnapshot?, correlatedRefresh: Bool) -> SnapshotDecision {
        guard let current else { return .replace }
        if incoming.phoneID != current.phoneID { return correlatedRefresh ? .replace : .ignore }
        return incoming.revision >= current.revision ? .advance : .ignore
    }
    static func overlay(_ title: NovaWatchTitle, commands: [NovaWatchCommand], phoneID: UUID?) -> NovaWatchTitle {
        var copy = title
        for command in commands where command.itemID == copy.id && command.phoneID == phoneID {
            switch command.action {
            case .setFavorite: copy.favorite = command.flag == true
            case .setQueued: copy.queued = command.flag == true
            case .setWatched:
                copy.watched = command.flag == true
                if command.flag == true { copy.queued = false }
                else { copy.position = 0; copy.lastPlayed = nil; copy.resumeAvailable = false }
            default: break
            }
        }
        return copy
    }
    static func validate(_ receipt: NovaWatchReceipt) throws {
        guard receipt.message.count <= 2000, WatchNightPlan.validDate(receipt.createdAt),
              (receipt.search?.count ?? 0) <= 25, (receipt.plans?.count ?? 0) <= 30,
              receipt.searchTotal.map({ $0 >= (receipt.search?.count ?? 0) }) ?? true,
              receipt.offset.map({ $0 >= 0 }) ?? true,
              receipt.query.map({ $0.count <= 100 }) ?? true else { throw NovaWatchFailure.invalid }
        if let title = receipt.updatedTitle { try NovaWatchCodec.validate(title) }
        try receipt.search?.forEach { try NovaWatchCodec.validate($0) }
        try receipt.plan?.validate()
        if let plans = receipt.plans {
            guard Set(plans.map(\.id)).count == plans.count, plans.allSatisfy({ !$0.name.isEmpty && $0.name.count <= 100 && (0...40).contains($0.count) && WatchNightPlan.validDate($0.startsAt) }) else { throw NovaWatchFailure.invalid }
        }
    }
    static func applying(_ title: NovaWatchTitle, to snapshot: NovaWatchSnapshot) -> NovaWatchSnapshot {
        var copy = snapshot
        copy.titles.removeAll { $0.id == title.id }; copy.titles.insert(title, at: 0)
        copy.titles = Array(copy.titles.prefix(120))
        copy.totalTitles = max(copy.totalTitles, copy.titles.count)
        return copy
    }
    static func boundedText(_ value: String, characters: Int, bytes: Int) -> String {
        var text = String(value.prefix(characters))
        while text.utf8.count > bytes && !text.isEmpty { text.removeLast() }
        return text == value ? text : text + "…"
    }
    static func live(_ snapshot: NovaWatchSnapshot?, reachable: Bool, now: Date = Date()) -> Bool {
        guard reachable, let snapshot, snapshot.phoneForeground else { return false }
        return (0..<20).contains(now.timeIntervalSince(snapshot.generatedAt))
    }
}
