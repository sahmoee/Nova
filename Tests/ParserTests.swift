//
//  ParserTests.swift
//  JooTVTests
//
//  Unit tests for the pure parsing helpers. They cover the tricky edge cases in
//  stream metadata parsing, SRT->VTT conversion, and SMB URL parsing.
//

import XCTest
@testable import Nova

final class StreamRankerTests: XCTestCase {

    func testParseQuality() {
        XCTAssertEqual(StreamRanker.parseQuality(from: "Movie 2160p HDR"), .uhd4k)
        XCTAssertEqual(StreamRanker.parseQuality(from: "Show.1080p.WEB"), .fhd1080)
        XCTAssertEqual(StreamRanker.parseQuality(from: "x264 720p"), .hd720)
        XCTAssertEqual(StreamRanker.parseQuality(from: "DVDRip 480p"), .sd480)
        XCTAssertEqual(StreamRanker.parseQuality(from: "CAM rip"), .cam)
        XCTAssertEqual(StreamRanker.parseQuality(from: "unknown release"), .unknown)
        XCTAssertEqual(StreamRanker.parseQuality(from: "4K UHD"), .uhd4k)
    }

    func testParseSize() {
        XCTAssertEqual(StreamRanker.parseSize(from: "File 1.5 GB"), Int64(1.5 * 1_073_741_824))
        XCTAssertEqual(StreamRanker.parseSize(from: "750 MB"), Int64(750 * 1_048_576))
        XCTAssertEqual(StreamRanker.parseSize(from: "size 2 GiB"), Int64(2 * 1_073_741_824))
        XCTAssertNil(StreamRanker.parseSize(from: "no size here"))
    }

    func testParseSeeders() {
        XCTAssertEqual(StreamRanker.parseSeeders(from: "👤 1234"), 1234)
        XCTAssertEqual(StreamRanker.parseSeeders(from: "Seeders: 56"), 56)
        XCTAssertEqual(StreamRanker.parseSeeders(from: "S:78"), 78)
        XCTAssertNil(StreamRanker.parseSeeders(from: "no seeders"))
    }

    func testRankingPrefersCachedThenQuality() {
        let cachedLow = StreamOption(addonName: "a", rawTitle: "480p", quality: .sd480, isCached: true)
        let uncachedHigh = StreamOption(addonName: "b", rawTitle: "1080p", quality: .fhd1080, isCached: false)
        let ranked = StreamRanker.rank([uncachedHigh, cachedLow])
        XCTAssertTrue(ranked.first?.isCached == true, "Cached stream should rank first")
    }

    func testAutoSelectRequireCachedFallsBackWhenNoneCached() {
        let a = StreamOption(addonName: "a", rawTitle: "1080p", quality: .fhd1080, isCached: false)
        let b = StreamOption(addonName: "b", rawTitle: "720p", quality: .hd720, isCached: false)
        let pick = StreamRanker.autoSelect([a, b], preferredQuality: nil, requireCached: true)
        XCTAssertNotNil(pick, "Should still pick a stream even if none are cached")
    }
}

final class SubtitleConverterTests: XCTestCase {

    func testSRTtoVTTAddsHeaderAndFixesTimestamps() {
        let srt = """
        1
        00:00:01,000 --> 00:00:04,000
        Hello world

        2
        00:00:05,500 --> 00:00:08,000
        Second line
        """
        let vtt = SubtitleConverter.srtToVTT(srt)
        XCTAssertTrue(vtt.hasPrefix("WEBVTT"), "VTT must start with WEBVTT header")
        XCTAssertTrue(vtt.contains("00:00:01.000 --> 00:00:04.000"), "Commas become dots")
        XCTAssertTrue(vtt.contains("Hello world"))
        XCTAssertFalse(vtt.contains("\n1\n"), "Numeric counters should be dropped")
    }

    func testAlreadyVTTPassthrough() {
        let vtt = "WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nHi"
        XCTAssertEqual(SubtitleConverter.srtToVTT(vtt), vtt)
    }
}

final class SMBURLParserTests: XCTestCase {

    func testPlainHostReturnsNil() {
        XCTAssertNil(SMBURLParser.parse("sowens.local"))
        XCTAssertNil(SMBURLParser.parse("192.168.1.10"))
    }

    func testSchemeStrippedHostOnly() {
        XCTAssertEqual(SMBURLParser.parse("smb://sowens.local"),
                       SMBURLParser.Parsed(host: "sowens.local", share: nil, path: nil))
    }

    func testFullPathSplit() {
        XCTAssertEqual(SMBURLParser.parse("smb://sowens.local/Home/Movies"),
                       SMBURLParser.Parsed(host: "sowens.local", share: "Home", path: "/Movies"))
    }

    func testHostAndShareNoScheme() {
        XCTAssertEqual(SMBURLParser.parse("sowens.local/Home"),
                       SMBURLParser.Parsed(host: "sowens.local", share: "Home", path: nil))
    }

    func testEmptyReturnsNil() {
        XCTAssertNil(SMBURLParser.parse("   "))
    }
}
