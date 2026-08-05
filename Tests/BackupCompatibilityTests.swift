import XCTest
@testable import Nova

final class BackupCompatibilityTests: XCTestCase {
    func testProductionCloudKeyRemainsStableAndIsNotDuplicated() {
        XCTAssertEqual(BackupCompatibility.currentCloudKey, "backup.snapshot.v1")
        XCTAssertFalse(BackupCompatibility.legacyCloudKeys.contains("backup.snapshot.v1"))
    }

    func testFrameTVV1SnapshotDecodesWithoutLiveTVField() throws {
        var legacy = BackupSnapshot()
        legacy.version = 1
        legacy.deviceName = "Living Room Apple TV"
        legacy.settings = [
            "home.route": .string("frametv://library"),
            "home.shelves.v1": .data(try JSONSerialization.data(withJSONObject: [
                ["title": "Continue Watching", "deepLink": "frametv://continue"]
            ]))
        ]
        legacy.smbSharesJSON = try JSONSerialization.data(withJSONObject: [
            ["name": "Movies", "callback": "frametv://settings/sources"]
        ])
        legacy.secrets = ["realdebrid.token": "leave-astra://secret-unchanged"]

        let encoded = try JSONEncoder().encode(legacy)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "liveTVJSON")
        let historicalData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try BackupCompatibility.decode(
            historicalData,
            fileName: "FrameTV-2026-06-27.frametv"
        )

        XCTAssertEqual(decoded.origin, .frameTV)
        XCTAssertTrue(decoded.wasNormalized)
        XCTAssertEqual(decoded.snapshot.version, 1)
        XCTAssertNil(decoded.snapshot.liveTVJSON)
        XCTAssertEqual(decoded.snapshot.secrets["realdebrid.token"], "leave-astra://secret-unchanged")

        guard case .string(let route) = decoded.snapshot.settings["home.route"] else {
            return XCTFail("Expected restored route string")
        }
        XCTAssertEqual(route, "nova://library")

        guard case .data(let shelvesData) = decoded.snapshot.settings["home.shelves.v1"],
              let shelves = try JSONSerialization.jsonObject(with: shelvesData) as? [[String: String]] else {
            return XCTFail("Expected restored shelves JSON")
        }
        XCTAssertEqual(shelves.first?["deepLink"], "nova://continue")

        let sharesData = try XCTUnwrap(decoded.snapshot.smbSharesJSON)
        let shares = try XCTUnwrap(
            JSONSerialization.jsonObject(with: sharesData) as? [[String: String]]
        )
        XCTAssertEqual(shares.first?["callback"], "nova://settings/sources")
    }

    func testAstraV2FileIsIdentifiedAndNormalized() throws {
        var astra = BackupSnapshot()
        astra.version = 2
        astra.settings = ["player.returnURL": .string("astra://movie/imdb:tt0111161")]

        let decoded = try BackupCompatibility.decode(
            JSONEncoder().encode(astra),
            fileName: "Astra-2026-07-12.astra"
        )

        XCTAssertEqual(decoded.origin, .astra)
        guard case .string(let route) = decoded.snapshot.settings["player.returnURL"] else {
            return XCTFail("Expected restored URL")
        }
        XCTAssertEqual(route, "nova://movie/imdb:tt0111161")
    }

    func testMissingLegacyCollectionsDecodeToEmptyValues() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "version": 1,
            "createdAt": 0,
            "deviceName": "FrameTV"
        ])

        let decoded = try BackupCompatibility.decode(data, fileName: "backup.frametv")

        XCTAssertTrue(decoded.snapshot.settings.isEmpty)
        XCTAssertTrue(decoded.snapshot.secrets.isEmpty)
        XCTAssertNil(decoded.snapshot.addonsJSON)
    }

    func testNovaFileRemainsNova() throws {
        let data = try JSONEncoder().encode(BackupSnapshot())
        let decoded = try BackupCompatibility.decode(data, fileName: "Nova-current.nova")

        XCTAssertEqual(decoded.origin, .nova)
        XCTAssertFalse(decoded.wasNormalized)
    }

    func testLegacyDeepLinksRemainRoutable() throws {
        XCTAssertEqual(
            DeepLink.parse(try XCTUnwrap(URL(string: "astra://library"))),
            .tab(.library)
        )
        XCTAssertEqual(
            DeepLink.parse(try XCTUnwrap(URL(string: "frametv://settings/sources"))),
            .settingsSources
        )
    }
}
