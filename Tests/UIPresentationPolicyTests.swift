import XCTest
@testable import Nova

@MainActor
final class UIPresentationPolicyTests: XCTestCase {
    func testSearchTrimsOnlyOuterWhitespace() {
        XCTAssertEqual(NovaPresentationPolicy.searchQuery("  English UK\n"), "English UK")
        XCTAssertEqual(NovaPresentationPolicy.searchQuery(" \n\t "), "")
        XCTAssertEqual(NovaPresentationPolicy.searchQuery("Sous-titré 日本語"), "Sous-titré 日本語")
    }

    func testProgressIsAlwaysFiniteAndBounded() {
        XCTAssertEqual(NovaPresentationPolicy.progress(.nan), 0)
        XCTAssertEqual(NovaPresentationPolicy.progress(.infinity), 0)
        XCTAssertEqual(NovaPresentationPolicy.progress(-0.4), 0)
        XCTAssertEqual(NovaPresentationPolicy.progress(1.4), 1)
        XCTAssertEqual(NovaPresentationPolicy.progress(0.45), 0.45)
    }

    func testDownloadRateCannotTrapIntegerConversion() {
        XCTAssertNil(NovaPresentationPolicy.rateBytes(nil))
        XCTAssertNil(NovaPresentationPolicy.rateBytes(.nan))
        XCTAssertNil(NovaPresentationPolicy.rateBytes(.infinity))
        XCTAssertNil(NovaPresentationPolicy.rateBytes(-1))
        XCTAssertNil(NovaPresentationPolicy.rateBytes(Double(Int64.max)))
        XCTAssertEqual(NovaPresentationPolicy.rateBytes(1024.5), 1024)
    }

    func testIdentityDeduplicationPreservesFirstProviderResult() {
        struct Track: Equatable { let id: String; let language: String }
        let english = Track(id: "en", language: "English")
        let french = Track(id: "fr", language: "French")
        let duplicate = Track(id: "en", language: "Duplicate English")
        XCTAssertEqual(NovaPresentationPolicy.unique([english, french, duplicate], by: \.id), [english, french])
        XCTAssertEqual(NovaPresentationPolicy.unique([Track](), by: \.id), [])
    }
}
