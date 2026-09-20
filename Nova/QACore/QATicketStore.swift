// QATicketStore.swift
// ─────────────────────────────────────────────────────────────────────────────
// Shared QACore — ticket persistence and sync.
//
// Tickets are press-and-hold reports: one sentence from the tester, everything
// else captured automatically. Ring buffer of 200, monotonic numbering per
// install, three sync destinations (worker, folder, optional cPanel).
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI
import UIKit
import ImageIO

@MainActor
@Observable
final class QATicketStore {
    static let shared = QATicketStore()

    private(set) var tickets: [QATicket] = []
    private let cap = 200

    private nonisolated static let ticketsKey = "qa.tickets.v1"
    private nonisolated static let seqKey = "qa.ticket.sequence.v1"

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var pendingShotWrites: [UUID: Task<Void, Never>] = [:]

    private init() { load() }

    // MARK: Directories

    var screenshotDirectory: URL? {
        try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true)
            .appendingPathComponent("QAScreenshots")
    }

    var mockupDirectory: URL? {
        try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true)
            .appendingPathComponent("QAMockups")
    }

    // MARK: Derived

    var open: [QATicket] { tickets.filter(\.needsAttention) }
    var openCount: Int { open.count }
    var blockers: [QATicket] { tickets.filter { $0.severity == .blocker && $0.needsAttention } }
    var unsynced: [QATicket] { tickets.filter { !$0.isSynced } }
    private(set) var lastSyncOutcome: String = "never published"
    private(set) var isSyncing = false

    // MARK: Numbering

    private func nextNumber() -> String {
        let d = UserDefaults.standard
        let next = d.integer(forKey: Self.seqKey) + 1
        d.set(next, forKey: Self.seqKey)
        return QAReportIdentity.ticketNumber(
            build: QA.config.buildNumber,
            sequence: next,
            installationID: QAIdentityStore.shared.installationID)
    }

    // MARK: Opening a ticket

    @discardableResult
    func open(title: String,
              body: String = "",
              severity: QATicketSeverity = .major,
              requiresManualReview: Bool = false,
              context: QATicketContext = QATicketContext(),
              origin: QATicketOrigin? = .tester,
              automaticCheckID: String? = nil,
              screenshot: UIImage? = nil) -> QATicket {
        let number = nextNumber()
        var ticket = QATicket(number: number, title: title)
        ticket.body = body
        ticket.severity = severity
        ticket.requiresManualReview = requiresManualReview
        ticket.context = context
        ticket.origin = origin
        ticket.automaticCheckID = automaticCheckID
        ticket.runID = QARunLog.activeRunID

        tickets.insert(ticket, at: 0)
        trim()

        QARecorder.shared.record(.note, label: "ticket opened", detail: "\(number) \(title)")

        if let image = screenshot {
            saveScreenshot(image, for: ticket.id)
        }

        save()
        scheduleLocalMirror(ticket.id)
        return ticket
    }

    // MARK: Updates

    func update(_ id: UUID, title: String? = nil, body: String? = nil,
                severity: QATicketSeverity? = nil, status: QATicketStatus? = nil,
                resolution: String? = nil) {
        guard let i = tickets.firstIndex(where: { $0.id == id }) else { return }
        if let t = title { tickets[i].title = t }
        if let b = body { tickets[i].body = b; tickets[i].editedAt = Date(); tickets[i].editCount = (tickets[i].editCount ?? 0) + 1 }
        if let s = severity { tickets[i].severity = s }
        if let st = status { tickets[i].status = st; if st == .verified { tickets[i].verifiedAt = Date() } }
        if let r = resolution { tickets[i].resolution = r }
        tickets[i].updatedAt = Date()
        tickets[i].syncedAt = nil
        save()
        scheduleLocalMirror(id)
    }

    func delete(_ id: UUID) {
        if let t = tickets.first(where: { $0.id == id }) { discardFiles(t) }
        tickets.removeAll { $0.id == id }
        save()
    }

    func clear() {
        tickets.forEach { discardFiles($0) }
        tickets.removeAll()
        UserDefaults.standard.set(0, forKey: Self.seqKey)
        save()
    }

    func linkCheck(_ id: UUID, check: String) {
        guard let i = tickets.firstIndex(where: { $0.id == id }) else { return }
        tickets[i].checkTicket = check
        save()
        scheduleLocalMirror(id)
    }

    func tickets(inRun runID: String) -> [QATicket] {
        tickets.filter { $0.runID == runID }
    }

    var recurring: [QATicket] {
        tickets.filter(\.isRecurring)
            .sorted { ($0.seenAgain ?? 0) > ($1.seenAgain ?? 0) }
    }

    // MARK: Screenshot

    private func saveScreenshot(_ image: UIImage, for id: UUID) {
        guard let dir = screenshotDirectory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "\(id.uuidString).jpg"
        let url = dir.appendingPathComponent(name)
        let task = Task.detached(priority: .utility) {
            image.jpegData(compressionQuality: 0.85).flatMap { try? $0.write(to: url) }
        }
        pendingShotWrites[id] = Task { _ = await task.value }
        Task { @MainActor in
            await task.value
            self.pendingShotWrites.removeValue(forKey: id)
            if let i = self.tickets.firstIndex(where: { $0.id == id }) {
                self.tickets[i].screenshotFile = name
                self.save()
            }
        }
    }

    private func awaitScreenshotWrite(_ id: UUID) async {
        if let t = pendingShotWrites[id] { await t.value }
    }

    private func removeScreenshot(_ ticket: QATicket) {
        guard let file = ticket.screenshotFile,
              let dir = screenshotDirectory else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(file))
    }

    private func removeMockupFile(_ ticket: QATicket) {
        guard let file = ticket.mockupFile,
              let dir = mockupDirectory else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(file))
    }

    private func discardFiles(_ ticket: QATicket) {
        removeScreenshot(ticket)
        removeMockupFile(ticket)
    }

    // MARK: Sync stamps

    func stampMirrored(_ id: UUID) {
        guard let i = tickets.firstIndex(where: { $0.id == id }) else { return }
        tickets[i].mirroredAt = Date()
        save()
    }

    func stampShotSynced(_ id: UUID) {
        guard let i = tickets.firstIndex(where: { $0.id == id }) else { return }
        tickets[i].shotSyncedAt = Date()
        save()
    }

    // MARK: Local folder mirror

    private func scheduleLocalMirror(_ id: UUID) {
        Task { @MainActor [weak self] in
            guard let self, let t = self.tickets.first(where: { $0.id == id }) else { return }
            await self.awaitScreenshotWrite(id)
            let md = self.markdown(for: t)
            await QAFolderMirror.shared.writeTicket(number: t.number, markdown: md)
            if let file = t.screenshotFile,
               let dir = self.screenshotDirectory {
                await QAFolderMirror.shared.copyScreenshot(
                    from: dir.appendingPathComponent(file),
                    ticketNumber: t.number)
            }
            self.stampMirrored(id)
        }
    }

    // MARK: Markdown export

    func markdown(for t: QATicket) -> String {
        var out: [String] = []
        out.append("# \(t.number) — \(t.title)")
        out.append("")
        out.append("**\(t.severity.title)** · \(t.statusLabel) · \(t.originPhrase) · \(t.createdAt.formatted())")
        if t.requiresManualReview == true {
            out.append("")
            out.append("> **REQUIRES MANUAL REVIEW:** Ask the tester for specifics before changing code.")
        }
        if !t.body.isEmpty {
            out.append("")
            out.append("## Report")
            out.append("")
            out.append(t.body)
        }
        out.append("")
        out.append("## Environment")
        out.append("")
        out.append(t.context.summaryLines.map { "- \($0)" }.joined(separator: "\n"))
        if !t.context.breadcrumbs.isEmpty {
            out.append("")
            out.append("## Steps before the report")
            out.append("")
            out.append(t.context.breadcrumbs.map { "- \($0)" }.joined(separator: "\n"))
        }
        out.append("")
        out.append("---")
        out.append("")
        out.append("_Written by \(QA.config.appName) QA \(QA.config.version) (\(QA.config.buildNumber))._")
        return out.joined(separator: "\n")
    }

    // MARK: Wire format

    func dictionary(for t: QATicket, thumbnail: String? = nil) -> [String: Any] {
        var out: [String: Any] = [
            "id": t.id.uuidString,
            "number": t.number,
            "title": t.title,
            "body": t.body,
            "severity": t.severity.rawValue,
            "status": t.status.rawValue,
            "createdAt": ISO8601DateFormatter().string(from: t.createdAt),
            "updatedAt": ISO8601DateFormatter().string(from: t.updatedAt),
            "screen": t.context.screen,
            "breadcrumbs": t.context.breadcrumbs,
            "runningProcesses": t.context.runningProcesses,
            "stalledProcesses": t.context.stalledProcesses,
            "recentFailures": t.context.recentFailures,
            "openViolations": t.context.openViolations,
            "hasScreenshot": t.screenshotFile != nil,
            "hasMockup": t.mockupFile != nil,
            "source": QA.config.source,
            "environment": [
                "appVersion": t.context.appVersion,
                "build": t.context.build,
                "device": t.context.device,
                "os": t.context.os,
                "memoryMB": Int(t.context.memoryMB),
                "thermal": t.context.thermal,
                "lowPower": t.context.lowPower,
                "online": t.context.online,
                "freeDiskMB": Int(t.context.freeDiskMB),
                "sessionDuration": t.context.sessionDuration,
                "tapsOnScreen": t.context.tapsOnScreen,
                "worstHitchMs": Int(t.context.worstHitchMs),
            ],
        ]
        if let identity = t.context.identity { out["qaIdentity"] = identity.dictionary }
        if let origin = t.origin { out["origin"] = origin.rawValue }
        if let checkID = t.automaticCheckID { out["automaticCheckID"] = checkID }
        if let env = t.context.environment { out["renderingEnvironment"] = env }
        if let trail = t.context.touchTrail, !trail.isEmpty { out["touchTrail"] = trail }
        if let resolution = t.resolution, !resolution.isEmpty { out["resolution"] = resolution }
        if let verifiedAt = t.verifiedAt { out["verifiedAt"] = ISO8601DateFormatter().string(from: verifiedAt) }
        if let dup = t.duplicateOf { out["duplicateOf"] = dup }
        if let sa = t.seenAgain { out["seenAgain"] = sa }
        if let rc = t.refileCount { out["refileCount"] = rc }
        if let ct = t.checkTicket { out["checkTicket"] = ct }
        if let run = t.runID { out["runID"] = run }
        if let mrr = t.requiresManualReview { out["requiresManualReview"] = mrr }
        if let thumb = thumbnail { out["thumbnail"] = thumb }
        return out
    }

    // MARK: Sorted / filtered

    func sorted(status: QATicketStatus?, severity: QATicketSeverity?, search: String) -> [QATicket] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return tickets.filter { t in
            (status == nil || t.status == status!) &&
            (severity == nil || t.severity == severity!) &&
            (q.isEmpty || t.title.lowercased().contains(q) || t.body.lowercased().contains(q) ||
             t.number.lowercased().contains(q))
        }
    }

    // MARK: Syncing

    @discardableResult
    func publish(_ id: UUID) async -> Bool {
        guard let ticket = tickets.first(where: { $0.id == id }) else { return false }
        return await push([ticket])
    }

    @discardableResult
    func publishUnsynced() async -> Bool {
        let pending = unsynced
        guard !pending.isEmpty else { return true }
        return await push(pending)
    }

    private func push(_ batch: [QATicket]) async -> Bool {
        guard !batch.isEmpty else { return true }
        isSyncing = true
        defer { isSyncing = false }

        let thumbs = await thumbnails(for: batch)
        let payload: [String: Any] = [
            "schema": "qa-report/v1",
            "kind": "tickets",
            "source": QA.config.source,
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "app": ["name": QA.config.appName,
                    "version": QA.config.version,
                    "build": QA.config.buildNumber],
            "tickets": batch.map { self.dictionary(for: $0, thumbnail: thumbs[$0.id]) },
        ]

        do {
            let ok = try await QAReportTransport.post(payload)
            let stamp = Date()
            for t in batch {
                guard let i = tickets.firstIndex(where: { $0.id == t.id }) else { continue }
                if ok {
                    tickets[i].syncedAt = stamp
                    tickets[i].syncError = ""
                } else {
                    tickets[i].syncError = "bridge rejected the ticket"
                }
            }
            lastSyncOutcome = ok
                ? "synced \(batch.count) ticket\(batch.count == 1 ? "" : "s") at \(stamp.formatted(date: .omitted, time: .shortened))"
                : "bridge rejected the batch"
            save()
            return ok
        } catch {
            for t in batch {
                guard let i = tickets.firstIndex(where: { $0.id == t.id }) else { continue }
                tickets[i].syncError = error.localizedDescription
            }
            lastSyncOutcome = error.localizedDescription
            save()
            return false
        }
    }

    private func thumbnails(for batch: [QATicket]) async -> [UUID: String] {
        guard let directory = screenshotDirectory else { return [:] }
        for ticket in batch { await awaitScreenshotWrite(ticket.id) }
        let files = batch.sorted { $0.createdAt > $1.createdAt }.compactMap { t -> (UUID, URL)? in
            guard let file = t.screenshotFile else { return nil }
            return (t.id, directory.appendingPathComponent(file))
        }
        return await Task.detached(priority: .utility) {
            let budget = 96 * 1024
            var spent = 0
            var out: [UUID: String] = [:]
            for (id, url) in files {
                guard !Task.isCancelled, spent < budget else { break }
                let encoded: String? = autoreleasepool {
                    guard let source = CGImageSourceCreateWithURL(url as CFURL,
                        [kCGImageSourceShouldCache: false] as CFDictionary),
                          let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceCreateThumbnailWithTransform: true,
                            kCGImageSourceThumbnailMaxPixelSize: 200
                          ] as CFDictionary) else { return nil }
                    return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.4)?.base64EncodedString()
                }
                guard let encoded else { continue }
                guard spent + encoded.count <= budget else { continue }
                out[id] = encoded
                spent += encoded.count
            }
            return out
        }.value
    }

    // MARK: Pull from worker

    @discardableResult
    func pullDeviceTickets() async -> Int {
        guard QAAccessGate.shared.isUnlocked else { return 0 }
        do {
            let rows = try await QAReportTransport.fetchDeviceTickets()
            var imported = 0
            for row in rows {
                guard let number = row["number"] as? String, !number.isEmpty,
                      let title = row["title"] as? String else { continue }
                if tickets.firstIndex(where: { $0.number == number }) == nil {
                    var t = QATicket(number: number, title: title)
                    t.body = row["body"] as? String ?? ""
                    t.severity = QATicketSeverity(rawValue: row["severity"] as? String ?? "") ?? .major
                    t.status = QATicketStatus(rawValue: row["status"] as? String ?? "") ?? .open
                    t.syncedAt = Date()
                    tickets.append(t)
                    imported += 1
                }
            }
            tickets.sort { $0.updatedAt > $1.updatedAt }
            if tickets.count > cap { trim() }
            save()
            return imported
        } catch {
            lastSyncOutcome = "device pull failed: \(error.localizedDescription)"
            return 0
        }
    }

    // MARK: Health summary

    var healthSummary: [String: Any] {
        [
            "total": tickets.count,
            "open": openCount,
            "blockers": blockers.count,
            "unsynced": unsynced.count,
            "numbers": open.prefix(20).map(\.number),
        ]
    }

    // MARK: Export

    var exportText: String {
        guard !tickets.isEmpty else { return "" }
        var out = ["TICKETS",
                   "\(tickets.count) total · \(openCount) open · \(blockers.count) blocker(s) · \(unsynced.count) unsynced",
                   ""]
        for t in sorted(status: nil, severity: nil, search: "") {
            out.append(t.exportText)
            out.append("")
        }
        return out.joined(separator: "\n")
    }

    // MARK: Persistence

    private func trim() {
        guard tickets.count > cap else { return }
        // Remove oldest non-blocker tickets first.
        let toRemove = tickets.count - cap
        var removed = 0
        tickets = tickets.filter { t in
            if removed < toRemove && t.severity != .blocker {
                removed += 1
                discardFiles(t)
                return false
            }
            return true
        }
    }

    private func save() {
        saveTask?.cancel()
        saveTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            // Snapshot on main actor, write off-main.
            let data: Data? = await MainActor.run {
                try? JSONEncoder().encode(self.tickets)
            }
            guard let data else { return }
            UserDefaults.standard.set(data, forKey: Self.ticketsKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.ticketsKey) else { return }
        // Element-by-element fallback decode for corruption tolerance.
        if let decoded = try? JSONDecoder().decode([QATicket].self, from: data) {
            tickets = decoded
            return
        }
        guard let rawArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        tickets = rawArray.compactMap { dict in
            guard let elem = try? JSONSerialization.data(withJSONObject: dict),
                  let t = try? JSONDecoder().decode(QATicket.self, from: elem) else { return nil }
            return t
        }
    }
}
