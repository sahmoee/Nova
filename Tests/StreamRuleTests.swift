//
//  StreamRuleTests.swift
//  NovaTests
//
//  User stream rules: matching, validation, ranking, auto-select and import.
//

import XCTest
@testable import Nova

@MainActor
final class StreamRuleTests: XCTestCase {

    private func stream(_ title: String, quality: StreamQuality = .fhd1080, cached: Bool = true) -> StreamOption {
        StreamOption(addonName: "Addon", rawTitle: title,
                     url: URL(string: "https://example.com/\(abs(title.hashValue))"),
                     quality: quality, isCached: cached)
    }

    func testTextRuleMatchesCaseInsensitively() {
        let engine = StreamRuleEngine(rules: [StreamRule(name: "Remux", pattern: "remux")])
        XCTAssertEqual(engine.matches(stream("Film.2160p.REMUX.mkv")).map(\.name), ["Remux"])
        XCTAssertTrue(engine.matches(stream("Film.1080p.WEB")).isEmpty)
    }

    func testRegexRuleAndDisabledRules() {
        let regex = StreamRule(name: "Atmos", pattern: #"(?i)(dolby\s*atmos|truehd)"#, isRegex: true)
        var off = StreamRule(name: "Off", pattern: "web")
        off.isEnabled = false
        let engine = StreamRuleEngine(rules: [regex, off])
        XCTAssertEqual(engine.matches(stream("Film TrueHD 7.1 WEB")).map(\.name), ["Atmos"])
    }

    func testValidationRejectsEmptyLongAndInvalidPatterns() {
        XCTAssertNotNil(StreamRuleEngine.validationError(for: StreamRule(name: "", pattern: "  ")))
        XCTAssertNotNil(StreamRuleEngine.validationError(for: StreamRule(name: "", pattern: String(repeating: "a", count: 201))))
        XCTAssertNotNil(StreamRuleEngine.validationError(for: StreamRule(name: "", pattern: "([", isRegex: true)))
        XCTAssertNil(StreamRuleEngine.validationError(for: StreamRule(name: "", pattern: "([", isRegex: false)))
        // Invalid regex rules are skipped rather than crashing the engine.
        XCTAssertTrue(StreamRuleEngine(rules: [StreamRule(name: "", pattern: "([", isRegex: true)]).isEmpty)
    }

    func testPreferAndAvoidShiftRanking() {
        let web = stream("Film 1080p WEB")
        let remux = stream("Film 1080p REMUX")
        var prefs = StreamRanker.StreamPreferences()
        prefs.rules = StreamRuleEngine(rules: [StreamRule(name: "R", pattern: "remux", effect: .prefer),
                                               StreamRule(name: "W", pattern: "web", effect: .avoid)])
        XCTAssertEqual(StreamRanker.rank([web, remux], preferences: prefs).first?.rawTitle, remux.rawTitle)
    }

    func testHiddenStreamsSinkAndAreNeverAutoSelected() {
        let cam = stream("Film CAM", quality: .uhd4k)
        let good = stream("Film 1080p WEB")
        var prefs = StreamRanker.StreamPreferences()
        prefs.rules = StreamRuleEngine(rules: [StreamRule(name: "Cam", pattern: "cam", effect: .hide)])
        XCTAssertEqual(StreamRanker.rank([cam, good], preferences: prefs).last?.rawTitle, cam.rawTitle)
        XCTAssertEqual(StreamRanker.autoSelect([cam, good], preferences: prefs, requireCached: false)?.rawTitle,
                       good.rawTitle)
    }

    func testAutoPlayRulesWinAutoSelectWhenTheyMatch() {
        let uhd = stream("Film 2160p", quality: .uhd4k)
        let favored = stream("Film 1080p FavoredGroup")
        var prefs = StreamRanker.StreamPreferences()
        prefs.rules = StreamRuleEngine(rules: [StreamRule(name: "Fav", pattern: "favoredgroup", autoPlay: true)])
        XCTAssertEqual(StreamRanker.autoSelect([uhd, favored], preferences: prefs, requireCached: false)?.rawTitle,
                       favored.rawTitle)
        // With no auto-play match, normal ranking applies.
        XCTAssertEqual(StreamRanker.autoSelect([uhd], preferences: prefs, requireCached: false)?.rawTitle,
                       uhd.rawTitle)
    }

    func testImportDropsInvalidRulesAndAssignsFreshIDs() throws {
        let original = StreamRule(name: "Good", pattern: "remux")
        let bad = StreamRule(name: "Bad", pattern: "([", isRegex: true)
        let json = String(data: try JSONEncoder().encode([original, bad]), encoding: .utf8)!
        let parsed = try StreamRuleStore.parseImport(json)
        XCTAssertEqual(parsed.map(\.name), ["Good"])
        XCTAssertNotEqual(parsed.first?.id, original.id)
        XCTAssertThrowsError(try StreamRuleStore.parseImport("not json"))
        XCTAssertThrowsError(try StreamRuleStore.parseImport(String(repeating: " ", count: 70_000)))
    }

    func testShelfConfigDecodesLegacyDataWithoutLayoutFields() throws {
        let legacy = #"{"id":"\#(UUID().uuidString)","kind":{"tmdbTrending":{}},"title":"Trending","isEnabled":true}"#
        let shelf = try JSONDecoder().decode(ShelfConfig.self, from: Data(legacy.utf8))
        XCTAssertNil(shelf.layout)
        XCTAssertFalse(shelf.isPinnedToTopRow)
        XCTAssertNil(shelf.itemLimit)
        XCTAssertEqual(shelf.contentType, .movie)
    }
}
