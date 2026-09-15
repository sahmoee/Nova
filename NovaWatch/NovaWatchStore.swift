import SwiftUI

private struct NovaWatchDiskState: Codable {
    var version = 1
    var outbox = NovaWatchOutbox()
    var snapshot: NovaWatchSnapshot?
    var receipts: [NovaWatchReceipt] = []
}

@MainActor
final class NovaWatchStore: ObservableObject {
    let connection = NovaWatchConnectivity()
    @Published private var disk = NovaWatchDiskState()
    @Published private(set) var blocked = false
    @Published var message: String?
    @Published private(set) var searchResults: [NovaWatchTitle] = []
    @Published private(set) var searchTotal = 0
    @Published private(set) var searchOffset = 0
    @Published private(set) var searching = false
    @Published private(set) var planSummaries: [NovaWatchPlanSummary] = []
    @Published private(set) var fetchedPlans: [UUID: WatchNightPlan] = [:]
    private var lastSearch: UUID?
    private var handshake: UUID?
    private var lastSent: (UUID, Date)?
    private var transient: [UUID: NovaWatchAction] = [:]
    private var requestedPlans: [UUID: UUID] = [:]
    private let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NovaWatch/state.json")
    var snapshot: NovaWatchSnapshot? { disk.snapshot }
    var pendingCount: Int { disk.outbox.commands.count }
    var receipts: [NovaWatchReceipt] { disk.receipts }
    var canEdit: Bool { !blocked && snapshot?.acceptsEdits == true }
    var live: Bool { NovaWatchPolicy.live(snapshot, reachable: connection.reachable) }
    var titles: [NovaWatchTitle] { (snapshot?.titles ?? []).map(overlay) }
    var plans: [NovaWatchPlanSummary] {
        let summaries = planSummaries.isEmpty ? (snapshot?.plans ?? []).map(NovaWatchPlanSummary.init) : planSummaries
        return summaries.sorted { $0.startsAt < $1.startsAt }
    }
    init() {
        do {
            if let saved = try NovaWatchCodec.read(NovaWatchDiskState.self, from: url) {
                guard saved.version == 1, saved.receipts.count <= 20 else { throw NovaWatchFailure.unreadable }
                try saved.outbox.validate(); if let snapshot = saved.snapshot { try NovaWatchCodec.validate(snapshot) }
                disk = saved
            }
        } catch { blocked = true; message = NovaWatchFailure.unreadable.localizedDescription }
        connection.onEnvelope = { [weak self] in self?.receive($0) }
        connection.onFailure = { [weak self] id in
            guard let self else { return }
            if id == self.lastSearch { self.searching = false }
            self.transient.removeValue(forKey: id)
            self.message = "iPhone did not confirm this request. Pending edits are kept; reconnect and Sync."
        }
        connection.onReady = { [weak self] in
            guard let self else { return }
            if self.connection.reachable { self.refresh() }
            self.flush()
        }
        connection.activate()
    }
    private func persist(_ candidate: NovaWatchDiskState) throws {
        guard !blocked else { throw NovaWatchFailure.unreadable }
        try NovaWatchCodec.write(candidate, to: url); disk = candidate
    }
    func resetLocalCache() {
        // Only the explicit watch recovery button discards its cached snapshot/outbox.
        do {
            let clean = NovaWatchDiskState(); try NovaWatchCodec.write(clean, to: url)
            connection.cancelPendingCommands()
            disk = clean; blocked = false; searchResults = []; searchTotal = 0; searchOffset = 0
            planSummaries = []; fetchedPlans = [:]; requestedPlans = [:]; transient = [:]
            lastSearch = nil; handshake = nil; lastSent = nil; searching = false
            message = "Watch cache cleared. A change already delivered to iPhone may still finish."
            refresh()
        }
        catch { message = error.localizedDescription }
    }
    func overlay(_ title: NovaWatchTitle) -> NovaWatchTitle {
        let latest = snapshot?.titles.first(where: { $0.id == title.id }) ?? title
        return NovaWatchPolicy.overlay(latest, commands: disk.outbox.commands, phoneID: snapshot?.phoneID)
    }

    func plan(_ id: UUID) -> WatchNightPlan? { fetchedPlans[id] ?? snapshot?.plans.first { $0.id == id } }
    func submit(_ action: NovaWatchAction, itemID: UUID? = nil, planID: UUID? = nil, entryID: UUID? = nil,
                flag: Bool? = nil, value: Double? = nil, text: String? = nil, date: Date? = nil, offset: Int? = nil, scope: NovaWatchLibraryScope? = nil) {
        do {
            guard !blocked else { throw NovaWatchFailure.unreadable }
            guard action == .refresh || snapshot != nil else { throw NovaWatchFailure.disconnected }
            guard action.isDurable || connection.reachable else { throw NovaWatchFailure.disconnected }
            if action.isRemote || action == .openOnPhone { guard live else { throw NovaWatchFailure.disconnected } }
            var candidate = disk
            var command = try candidate.outbox.make(phoneID: snapshot?.phoneID ?? UUID(), action: action)
            command.itemID = itemID; command.planID = planID; command.entryID = entryID
            command.flag = flag; command.value = value; command.text = text; command.date = date; command.offset = offset; command.scope = scope
            command.playerSessionID = snapshot?.player?.sessionID
            try command.validate()
            if action.isDurable { candidate.outbox.commands.append(command) }
            try persist(candidate)
            if action.isDurable { message = "Change queued for iPhone"; flush() }
            else {
                if action == .refresh { handshake = command.id }
                if action == .search { lastSearch = command.id; searching = true }
                transient[command.id] = action
                if action == .planDetails { requestedPlans[command.id] = command.planID }
                // This is an in-memory response routing table, never an offline command queue.
                if transient.count > 32 { transient = [command.id: action]; requestedPlans = [:] }
                try connection.send(command, durable: false)
            }
        } catch { searching = false; message = error.localizedDescription }
    }
    func refresh() {
        guard connection.reachable, !blocked else { return }
        submit(.refresh); lastSent = nil; flush()
    }
    func search(_ query: String, offset: Int = 0, scope: NovaWatchLibraryScope = .all) { submit(.search, text: String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100)), offset: offset, scope: scope) }
    func loadPlans() { if connection.reachable { submit(.plans) } }
    func loadPlan(_ id: UUID) { if connection.reachable { submit(.planDetails, planID: id) } }
    private func flush() {
        guard !blocked, let command = disk.outbox.commands.first, command.phoneID == snapshot?.phoneID else { return }
        if let lastSent, lastSent.0 == command.id, Date().timeIntervalSince(lastSent.1) < 10 { return }
        do { try connection.send(command, durable: true); lastSent = (command.id, Date()) }
        catch { message = "Pending changes will sync when your companion is available." }
    }
    private func receive(_ data: Data) {
        do {
            let envelope = try NovaWatchCodec.decode(NovaWatchEnvelope.self, data: data)
            guard envelope.version == 1 else { throw NovaWatchFailure.invalid }
            var candidate = disk
            if let snapshot = envelope.snapshot {
                try NovaWatchCodec.validate(snapshot)
                let isHandshake = envelope.receipt?.id == handshake && envelope.receipt?.outcome == .applied
                switch NovaWatchPolicy.decision(incoming: snapshot, current: candidate.snapshot, correlatedRefresh: isHandshake) {
                case .replace:
                    if !candidate.outbox.commands.isEmpty {
                        message = "iPhone data changed. Old pending edits were not applied."
                        for command in candidate.outbox.commands { candidate.receipts.append(NovaWatchReceipt(id: command.id, outcome: .rejected, message: "Discarded after iPhone reset or replacement.")) }
                        candidate.outbox.commands.removeAll()
                    }
                    searchResults = []; fetchedPlans = [:]; planSummaries = []; transient = [:]; requestedPlans = [:]; lastSearch = nil
                    candidate.snapshot = snapshot
                case .advance: candidate.snapshot = snapshot
                case .ignore:
                    if snapshot.phoneID != candidate.snapshot?.phoneID { message = "iPhone data changed. Tap Sync while Nova is open on iPhone." }
                }
            }

            if let receipt = envelope.receipt {
                try NovaWatchPolicy.validate(receipt)
                if let first = candidate.outbox.commands.first, first.id == receipt.id {
                    candidate.outbox.commands.removeFirst()
                    candidate.receipts.append(receipt); message = receipt.message; lastSent = nil
                    if receipt.outcome == .applied, let updated = receipt.updatedTitle {
                        if let snapshot = candidate.snapshot { candidate.snapshot = NovaWatchPolicy.applying(updated, to: snapshot) }
                        if let index = searchResults.firstIndex(where: { $0.id == updated.id }) { searchResults[index] = updated }
                    }
                    if first.planID != nil { fetchedPlans = [:]; planSummaries = [] }
                }
                if receipt.id == lastSearch {
                    searchResults = receipt.search ?? []; searchTotal = receipt.searchTotal ?? 0; searchOffset = receipt.offset ?? 0; searching = false
                }
                if transient.removeValue(forKey: receipt.id) != nil {
                    if let plans = receipt.plans { planSummaries = plans }
                    if let plan = receipt.plan { fetchedPlans[plan.id] = plan }
                    else if let id = requestedPlans[receipt.id], receipt.outcome == .applied {
                        fetchedPlans.removeValue(forKey: id); candidate.snapshot?.plans.removeAll { $0.id == id }; planSummaries.removeAll { $0.id == id }
                    }
                    requestedPlans.removeValue(forKey: receipt.id)
                    if receipt.outcome != .applied || (receipt.search == nil && receipt.plans == nil && receipt.plan == nil) { message = receipt.message }
                }
                if receipt.id == handshake { handshake = nil }
            }
            candidate.receipts = Array(candidate.receipts.suffix(20))
            try persist(candidate); flush()
        } catch { message = "Could not save companion data. Your pending edits are kept. \(error.localizedDescription)" }
    }
    func finishBackgroundDelivery() async {
        // WC delivers synchronously into our main actor callback; allow queued hops to
        // drain while retaining the system's watch-connectivity background assertion.
        connection.activate()
        var quiet = 0
        for _ in 0..<40 {
            if Task.isCancelled { return }
            await Task.yield()
            if connection.available && !connection.hasPendingContent && connection.pendingDeliveries == 0 { quiet += 1 } else { quiet = 0 }
            if quiet >= 3 { return }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }
}
