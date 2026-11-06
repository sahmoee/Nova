#if DEBUG
import CloudKit
import CryptoKit
import Foundation

/// Record transport for playback checkpoints. A reset is a newer checkpoint with
/// no last-played date, so a stale device cannot restore the old resume position.
@MainActor
final class CloudPlaybackSync: CKSyncEngineDelegate {
    struct Checkpoint: Codable, Equatable, Sendable {
        let position: TimeInterval
        let duration: TimeInterval?
        let lastPlayed: Date?
        let revision: Date
        let operation: UUID
        var libraryRecord: CloudLibraryRecord?
        var historyTitle: String?

        func supersedes(_ other: Self) -> Bool {
            if revision != other.revision { return revision > other.revision }
            return operation.uuidString > other.operation.uuidString
        }
    }

    private struct Entry: Codable {
        var checkpoint: Checkpoint
        var systemFields: Data?
        var pending: Bool
        var legacyImport: Bool?
    }

    private struct Journal: Codable {
        var entries: [String: Entry] = [:]
        var engineState: CKSyncEngine.State.Serialization?
    }

    private static let zone = CKRecordZone(zoneName: "NovaPlayback")
    private static let recordType = "PlaybackCheckpoint"
    private let account: CKRecord.ID
    private let file: URL
    private var journal: Journal
    private var engine: CKSyncEngine?
    private var canAdvanceFetchState = true
    private(set) var isConnected = true
    private let apply: (String, Checkpoint) -> Void
    private let report: (String) -> Void

    init(database: CKDatabase, account: CKRecord.ID, file: URL,
         apply: @escaping (String, Checkpoint) -> Void,
         report: @escaping (String) -> Void) throws {
        self.account = account
        self.file = file
        self.apply = apply
        self.report = report
        if FileManager.default.fileExists(atPath: file.path) {
            journal = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: file))
        } else {
            journal = Journal()
        }
        let configuration = CKSyncEngine.Configuration(
            database: database, stateSerialization: journal.engineState, delegate: self)
        let engine = CKSyncEngine(configuration)
        self.engine = engine
        if journal.engineState == nil {
            engine.state.add(pendingDatabaseChanges: [.saveZone(Self.zone)])
        }
        for (name, entry) in journal.entries where entry.pending {
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID(name))])
        }
    }

    static func recordName(for contentKey: String) -> String {
        SHA256.hash(data: Data(contentKey.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func enqueue(_ checkpoints: [String: Checkpoint]) -> Bool {
        guard let engine else { return false }
        var candidate = journal
        var changed: [CKSyncEngine.PendingRecordZoneChange] = []
        for (name, checkpoint) in checkpoints {
            let previous = candidate.entries[name]
            if let previous, !checkpoint.supersedes(previous.checkpoint) { continue }
            candidate.entries[name] = Entry(checkpoint: checkpoint, systemFields: previous?.systemFields, pending: true)
            changed.append(.saveRecord(recordID(name)))
        }
        guard !changed.isEmpty else { return true }
        guard commit(candidate) else { return false }
        engine.state.add(pendingRecordZoneChanges: changed)
        return true
    }

    func libraryRecords(after deletion: Double) -> [CloudLibraryRecord] {
        journal.entries.values.compactMap {
            let checkpoint = $0.checkpoint
            guard checkpoint.revision.timeIntervalSince1970 > deletion else { return nil }
            return checkpoint.libraryRecord
        }
    }

    func replay() {
        guard isConnected else { return }
        for (name, entry) in journal.entries where entry.checkpoint.libraryRecord == nil {
            apply(name, entry.checkpoint)
        }
    }

    func refresh(importLegacy: () -> [String: Checkpoint]) async -> Bool {
        guard let engine else { return false }
        do {
            try await engine.fetchChanges()
            guard self.engine === engine, canAdvanceFetchState else { return false }
            guard seedMissing(importLegacy(), engine: engine) else { return false }
            try await engine.sendChanges()
            return self.engine === engine && canAdvanceFetchState
                && engine.state.pendingDatabaseChanges.isEmpty
                && !journal.entries.values.contains(where: \.pending)
        } catch {
            report(error.localizedDescription)
            return false
        }
    }

    private func seedMissing(_ checkpoints: [String: Checkpoint], engine: CKSyncEngine) -> Bool {
        let missing = checkpoints.filter { journal.entries[$0.key] == nil }
        guard !missing.isEmpty else { return true }
        var candidate = journal
        for (name, checkpoint) in missing {
            candidate.entries[name] = Entry(checkpoint: checkpoint, pending: true, legacyImport: true)
        }
        guard commit(candidate) else { return false }
        engine.state.add(pendingRecordZoneChanges: missing.keys.map { .saveRecord(recordID($0)) })
        return true
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard engine === syncEngine else { return }
        switch event {
        case .stateUpdate(let event):
            guard canAdvanceFetchState else { return }
            var candidate = journal
            candidate.engineState = event.stateSerialization
            _ = commit(candidate)
        case .accountChange(let event):
            if case .signIn(let currentUser) = event.changeType, currentUser == account { return }
            engine = nil
            isConnected = false
            report("The iCloud account changed. Restart Nova to reconnect playback sync.")
        case .fetchedRecordZoneChanges(let event):
            for modification in event.modifications {
                reconcile(modification.record, acknowledged: false, engine: syncEngine)
            }
        case .sentRecordZoneChanges(let event):
            for record in event.savedRecords {
                reconcile(record, acknowledged: true, engine: syncEngine)
            }
            for failure in event.failedRecordSaves {
                if failure.error.code == .serverRecordChanged, let server = failure.error.serverRecord {
                    reconcile(server, acknowledged: false, engine: syncEngine)
                } else if failure.error.code == .zoneNotFound {
                    syncEngine.state.add(pendingDatabaseChanges: [.saveZone(Self.zone)])
                    syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(failure.record.recordID)])
                } else {
                    report(failure.error.localizedDescription)
                }
            }
        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard engine === syncEngine else { return nil }
        let scope = context.options.scope
        var records: [CKRecord] = []
        for change in syncEngine.state.pendingRecordZoneChanges where scope.contains(change) {
            guard case .saveRecord(let id) = change,
                  id.zoneID == Self.zone.zoneID,
                  let entry = journal.entries[id.recordName], entry.pending,
                  let payload = try? JSONEncoder().encode(entry.checkpoint) else { continue }
            let record = restoredRecord(from: entry.systemFields)
                ?? CKRecord(recordType: Self.recordType, recordID: id)
            record["checkpoint"] = payload as NSData
            records.append(record)
            if records.count == 200 { break }
        }
        return records.isEmpty ? nil : .init(recordsToSave: records)
    }

    private func recordID(_ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: Self.zone.zoneID)
    }

    private func reconcile(_ record: CKRecord, acknowledged: Bool, engine: CKSyncEngine) {
        guard record.recordType == Self.recordType, record.recordID.zoneID == Self.zone.zoneID,
              let payload = record["checkpoint"] as? Data,
              let remote = try? JSONDecoder().decode(Checkpoint.self, from: payload),
              remote.position.isFinite, remote.position >= 0 else { return }
        let name = record.recordID.recordName
        let fields = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: fields)
        fields.finishEncoding()

        var candidate = journal
        let previous = candidate.entries[name]
        if let previous, previous.legacyImport != true, previous.checkpoint.supersedes(remote) {
            candidate.entries[name] = Entry(checkpoint: previous.checkpoint,
                                            systemFields: fields.encodedData, pending: true)
            guard commit(candidate) else {
                canAdvanceFetchState = false
                return
            }
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
            return
        }

        candidate.entries[name] = Entry(checkpoint: remote, systemFields: fields.encodedData, pending: false)
        guard commit(candidate) else {
            canAdvanceFetchState = false
            return
        }
        engine.state.remove(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
        if !acknowledged, previous?.checkpoint != remote { apply(name, remote) }
    }

    private func restoredRecord(from fields: Data?) -> CKRecord? {
        guard let fields, let decoder = try? NSKeyedUnarchiver(forReadingFrom: fields) else { return nil }
        decoder.requiresSecureCoding = true
        defer { decoder.finishDecoding() }
        return CKRecord(coder: decoder)
    }

    @discardableResult
    private func commit(_ candidate: Journal) -> Bool {
        do {
            try JSONEncoder().encode(candidate).write(to: file, options: .atomic)
            journal = candidate
            return true
        } catch {
            report(error.localizedDescription)
            return false
        }
    }
}
#endif
