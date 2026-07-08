//
//  StreamFilterParserTests.swift
//  AstraTests
//
//  Pure-function tests for the natural-language stream filter parser.
//  NOTE: The project has no test target yet; add one in Xcode (File > New >
//  Target > Unit Testing Bundle, name AstraTests) and these files compile as-is.
//

import XCTest
@testable import Astra

final class StreamFilterParserTests: XCTestCase {

    func testEmptyPhraseParsesEmptyFilter() {
        XCTAssertTrue(StreamFilterParser.parse("").isEmpty)
        XCTAssertTrue(StreamFilterParser.parse("   ").isEmpty)
    }

    func testQualityKeywords() {
        XCTAssertEqual(StreamFilterParser.parse("4k only please").minQuality, .uhd4k)
        XCTAssertEqual(StreamFilterParser.parse("2160p rip").minQuality, .uhd4k)
        XCTAssertEqual(StreamFilterParser.parse("1080 or better").minQuality, .fhd1080)
        XCTAssertEqual(StreamFilterParser.parse("full hd").minQuality, .fhd1080)
        XCTAssertEqual(StreamFilterParser.parse("720p is fine").minQuality, .hd720)
        XCTAssertNil(StreamFilterParser.parse("just something good").minQuality)
    }

    func testCachedKeywords() {
        XCTAssertTrue(StreamFilterParser.parse("cached only").cachedOnly)
        XCTAssertTrue(StreamFilterParser.parse("instant sources").cachedOnly)
        XCTAssertTrue(StreamFilterParser.parse("debrid").cachedOnly)
        XCTAssertFalse(StreamFilterParser.parse("1080p").cachedOnly)
    }

    func testSizeParsing() {
        XCTAssertEqual(StreamFilterParser.parse("under 8gb").maxSizeGB, 8)
        XCTAssertEqual(StreamFilterParser.parse("max 5 gb").maxSizeGB, 5)
        XCTAssertNil(StreamFilterParser.parse("a big file").maxSizeGB)
    }

    func testLanguageParsing() {
        XCTAssertEqual(StreamFilterParser.parse("english audio").language, "EN")
        XCTAssertEqual(StreamFilterParser.parse("spanish dub").language, "ES")
        XCTAssertNil(StreamFilterParser.parse("1080p cached").language)
    }

    func testCodecAndHDR() {
        XCTAssertTrue(StreamFilterParser.parse("hevc please").codecPreferred)
        XCTAssertTrue(StreamFilterParser.parse("av1").codecPreferred)
        XCTAssertTrue(StreamFilterParser.parse("hdr").hdrOnly)
        XCTAssertTrue(StreamFilterParser.parse("dolby vision").hdrOnly)
    }

    func testCombinedPhrase() {
        let f = StreamFilterParser.parse("cached 4k hdr under 10gb english hevc")
        XCTAssertEqual(f.minQuality, .uhd4k)
        XCTAssertTrue(f.cachedOnly)
        XCTAssertTrue(f.hdrOnly)
        XCTAssertEqual(f.maxSizeGB, 10)
        XCTAssertEqual(f.language, "EN")
        XCTAssertTrue(f.codecPreferred)
        XCTAssertFalse(f.isEmpty)
    }
}
