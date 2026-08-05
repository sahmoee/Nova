import XCTest
@testable import Nova

final class AddonSecurityTests: XCTestCase {
    func testConfiguredManifestURLIsRedactedForPersistence() throws {
        let original = try XCTUnwrap(URL(string: "https://example.aiostreams.app/private-token/manifest.json"))
        let addon = InstalledAddon(manifestURL: original, name: "Configured")

        XCTAssertTrue(addon.manifestURLContainsSensitiveConfiguration)
        XCTAssertEqual(addon.redactedManifestURL.absoluteString,
                       "https://example.aiostreams.app/manifest.json")
        XCTAssertFalse(addon.redactedManifestURL.absoluteString.contains("private-token"))
    }

    func testSensitiveQueryItemsAndUserInfoAreRemoved() throws {
        let original = try XCTUnwrap(URL(string: "https://user:pass@example.com/manifest.json?token=secret&region=us"))
        let addon = InstalledAddon(manifestURL: original, name: "Query Configured")
        let redacted = try XCTUnwrap(URLComponents(url: addon.redactedManifestURL,
                                                  resolvingAgainstBaseURL: false))

        XCTAssertNil(redacted.user)
        XCTAssertNil(redacted.password)
        XCTAssertEqual(redacted.queryItems, [URLQueryItem(name: "region", value: "us")])
    }
}
