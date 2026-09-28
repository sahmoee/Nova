import XCTest
@testable import Nova

final class StreamResolverMagnetTests: XCTestCase {
    func testValidHexInfoHashBuildsMagnet() throws {
        let hash = "0123456789abcdefABCDEF0123456789abcdef01"
        let magnet = try XCTUnwrap(StreamResolver.magnet(fromHash: hash, name: nil))

        XCTAssertTrue(magnet.hasPrefix("magnet:?xt=urn:btih:\(hash)"))
        XCTAssertFalse(magnet.contains("&dn="))
    }

    func testValidBase32InfoHashBuildsMagnet() throws {
        let hash = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        let magnet = try XCTUnwrap(StreamResolver.magnet(fromHash: hash, name: nil))

        XCTAssertTrue(magnet.hasPrefix("magnet:?xt=urn:btih:\(hash)"))
    }

    func testHashWithInjectedParametersIsRejected() {
        let malicious = "0123456789abcdef0123456789abcdef01234567&tr=http://evil.example/announce"

        XCTAssertFalse(StreamResolver.isValidInfoHash(malicious))
        XCTAssertNil(StreamResolver.magnet(fromHash: malicious, name: "Movie"))
    }

    func testWrongLengthOrAlphabetIsRejected() {
        XCTAssertNil(StreamResolver.magnet(fromHash: "", name: nil))
        XCTAssertNil(StreamResolver.magnet(fromHash: "abc123", name: nil))
        // 40 characters, but not hex.
        XCTAssertNil(StreamResolver.magnet(fromHash: String(repeating: "z", count: 40), name: nil))
        // 32 characters, but '0', '1', '8', '9' are not base32 digits.
        XCTAssertNil(StreamResolver.magnet(fromHash: String(repeating: "1", count: 32), name: nil))
    }

    func testDisplayNameCannotInjectParameters() throws {
        let hash = String(repeating: "a", count: 40)
        let magnet = try XCTUnwrap(StreamResolver.magnet(fromHash: hash, name: "Movie&xt=urn:btih:evil"))
        let components = try XCTUnwrap(URLComponents(string: magnet))
        let items = components.queryItems ?? []

        XCTAssertEqual(items.filter { $0.name == "xt" }.count, 1)
        XCTAssertEqual(items.first { $0.name == "dn" }?.value, "Movie&xt=urn:btih:evil")
    }
}
