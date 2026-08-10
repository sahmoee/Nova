import XCTest
@testable import Nova

final class BackupCompatibilityTests: XCTestCase {
    func testProductionCloudKeyRemainsStable() {
        XCTAssertEqual(BackupCompatibility.currentCloudKey, "backup.snapshot.v1")
        XCTAssertNotEqual(BackupCompatibility.writerCloudKey, BackupCompatibility.currentCloudKey)
    }

    func testSupportedFileExtensionsAreNovaOnly() {
        XCTAssertEqual(BackupCompatibility.supportedFileExtensions, ["nova", "json"])
    }

    func testNovaFileRemainsNovaAndUnchanged() throws {
        let data = try JSONEncoder().encode(BackupSnapshot())
        let decoded = try BackupCompatibility.decode(data, fileName: "Nova-current.nova")

        XCTAssertEqual(decoded.origin, .nova)
        XCTAssertFalse(decoded.wasNormalized)
    }

    func testUnmarkedV1SnapshotDecodesAsImported() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "version": 1,
            "createdAt": 0,
            "deviceName": "Living Room"
        ])

        let decoded = try BackupCompatibility.decode(data, fileName: "snapshot.json")

        XCTAssertEqual(decoded.origin, .imported)
        XCTAssertTrue(decoded.snapshot.settings.isEmpty)
        XCTAssertTrue(decoded.snapshot.secrets.isEmpty)
        XCTAssertNil(decoded.snapshot.addonsJSON)
    }

    func testDecodePreservesModernSnapshotContents() throws {
        var snap = BackupSnapshot()
        snap.version = 2
        snap.settings = ["player.returnURL": .string("nova://movie/imdb:tt0111161")]

        let decoded = try BackupCompatibility.decode(
            try JSONEncoder().encode(snap),
            fileName: "Nova-2026-08-08.nova"
        )

        XCTAssertEqual(decoded.origin, .nova)
        guard case .string(let route) = decoded.snapshot.settings["player.returnURL"] else {
            return XCTFail("Expected restored URL")
        }
        XCTAssertEqual(route, "nova://movie/imdb:tt0111161")
    }

    func testOnlyNovaSchemeIsRoutable() throws {
        XCTAssertEqual(
            DeepLink.parse(try XCTUnwrap(URL(string: "nova://library"))),
            .tab(.library)
        )
        XCTAssertNil(DeepLink.parse(try XCTUnwrap(URL(string: "astra://library"))))
        XCTAssertNil(DeepLink.parse(try XCTUnwrap(URL(string: "frametv://settings/sources"))))
    }
}
