import XCTest
@testable import Nova

final class SettingsDataPolicyTests: XCTestCase {
    func testLegacySnapshotStillRestoresUndeletedCategories() throws {
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "deviceName": "Legacy TV"])
        let snapshot = try JSONDecoder().decode(BackupSnapshot.self, from: data)
        XCTAssertTrue(snapshot.deletionAcknowledgements.isEmpty)
        XCTAssertTrue(SettingsDataPolicy.acceptsSnapshot(acknowledgedDeletion: 0, deletedAt: 0, paused: false))
    }

    func testNewTimestampCannotMakeLegacyBackupResurrectDeletedCategories() {
        var snapshot = BackupSnapshot()
        snapshot.createdAt = Date(timeIntervalSince1970: 500)
        snapshot.settings = ["settings.autoPlayNext": .bool(true), "stream.history.v1": .data(Data("old history".utf8))]
        snapshot.addonsJSON = Data("old addons".utf8)
        snapshot.smbSharesJSON = Data("unrelated sources".utf8)
        let safe = SettingsDataPolicy.sanitizeSnapshot(snapshot,
            deletedAt: [.preferences: 100, .history: 100, .addons: 100], paused: [])
        XCTAssertTrue(safe.settings.isEmpty)
        XCTAssertNil(safe.addonsJSON)
        XCTAssertEqual(safe.smbSharesJSON, snapshot.smbSharesJSON)
    }

    func testAcknowledgedBackupRestoresOnlyAcknowledgedCategory() throws {
        var snapshot = BackupSnapshot()
        snapshot.settings = ["settings.autoPlayNext": .bool(false), "stream.history.v1": .data(Data())]
        snapshot.deletionAcknowledgements = ["preferences": 100]
        let decoded = try JSONDecoder().decode(BackupSnapshot.self, from: JSONEncoder().encode(snapshot))
        let safe = SettingsDataPolicy.sanitizeSnapshot(decoded, deletedAt: [.preferences: 100, .history: 100], paused: [])
        XCTAssertEqual(safe.settings["settings.autoPlayNext"], .bool(false))
        XCTAssertNil(safe.settings["stream.history.v1"])
    }

    func testDeviceOnlyResetPreservesSharedAutomaticBackup() {
        var prior = BackupSnapshot()
        prior.settings = ["settings.autoPlayNext": .bool(false), "stream.history.v1": .data(Data("history".utf8))]
        prior.addonsJSON = Data("addons".utf8)
        var current = BackupSnapshot()
        current.settings = ["settings.autoPlayNext": .bool(true)]
        current.addonsJSON = Data("[]".utf8)
        current.smbSharesJSON = Data("new source".utf8)
        let backup = SettingsDataPolicy.preservingPausedCategories(in: current, previous: prior,
            paused: [.preferences, .history, .addons])
        XCTAssertEqual(backup.settings, prior.settings)
        XCTAssertEqual(backup.addonsJSON, prior.addonsJSON)
        XCTAssertEqual(backup.smbSharesJSON, current.smbSharesJSON)
    }

    func testPausedCategoryWithoutPriorBackupIsOmitted() {
        var snapshot = BackupSnapshot()
        snapshot.settings = ["settings.autoPlayNext": .bool(true)]
        snapshot.addonsJSON = Data("[]".utf8)
        let backup = SettingsDataPolicy.preservingPausedCategories(in: snapshot, previous: nil,
            paused: [.preferences, .addons])
        XCTAssertTrue(backup.settings.isEmpty)
        XCTAssertNil(backup.addonsJSON)
    }

    func testUnknownSnapshotKeysCannotChangeUnrelatedDefaults() {
        var snapshot = BackupSnapshot()
        snapshot.settings = ["nova.data.deletedAt.addons": .double(0), "unrelated.system.key": .bool(true),
                             "settings.resumePlayback": .bool(true)]
        let safe = SettingsDataPolicy.sanitizeSnapshot(snapshot, deletedAt: [:], paused: [])
        XCTAssertEqual(Set(safe.settings.keys), ["settings.resumePlayback"])
    }

    func testPrivateSnapshotURLValidation() {
        XCTAssertNotNil(SettingsDataPolicy.validSnapshotURL("http://100.100.100.100/setup.nova"))
        XCTAssertNotNil(SettingsDataPolicy.validSnapshotURL("https://personal.example/setup.nova?token=opaque"))
        for value in ["file:///etc/passwd", "https://user:password@example.com/setup", "https://example.com/setup#fragment", "relative.nova"] {
            XCTAssertNil(SettingsDataPolicy.validSnapshotURL(value))
        }
    }

    func testTombstoneRejectsOldAndNonfiniteRevisions() {
        for revision in [0, 100, Double.nan, Double.infinity] {
            XCTAssertFalse(SettingsDataPolicy.accepts(revision: revision, deletedAt: 100, paused: false))
        }
        XCTAssertTrue(SettingsDataPolicy.accepts(revision: 101, deletedAt: 100, paused: false))
        XCTAssertFalse(SettingsDataPolicy.accepts(revision: 101, deletedAt: 100, paused: true))
    }

    func testFeedbackAliasesShareThePreferenceDeletionBoundary() {
        XCTAssertEqual(SettingsDataPolicy.domain(for: "reco.feedback.v1"), .preferences)
        XCTAssertEqual(SettingsDataPolicy.domain(for: "cloud.reco.feedback.v1"), .preferences)
        XCTAssertEqual(SettingsDataPolicy.cloudPreferenceKey(for: "reco.feedback.v1"), "cloud.reco.feedback.v1")
        XCTAssertEqual(SettingsDataPolicy.localPreferenceKey(for: "cloud.reco.feedback.v1"), "reco.feedback.v1")
    }
}
