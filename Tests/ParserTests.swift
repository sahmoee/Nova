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

    func testPlainHostIsAccepted() {
        XCTAssertEqual(
            SMBURLParser.parse("sowens.local"),
            SMBURLParser.Parsed(host: "sowens.local", share: nil, path: nil)
        )
        XCTAssertEqual(
            SMBURLParser.parse("192.168.1.10"),
            SMBURLParser.Parsed(host: "192.168.1.10", share: nil, path: nil)
        )
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

    func testTailscaleMagicDNSNameIsAccepted() {
        XCTAssertEqual(SMBURLParser.parse("smb://server-mac.example-tailnet.ts.net/Media"),
                       SMBURLParser.Parsed(host: "server-mac.example-tailnet.ts.net", share: "Media", path: nil))
        XCTAssertTrue(SMBHostResolver.isTailscaleName("server-mac.example-tailnet.ts.net"))
        XCTAssertFalse(SMBHostResolver.isTailscaleName("192.168.1.10"))
    }
}

final class KodiRepositoryParserTests: XCTestCase {
    func testParsesRepositoryAddonAndResolvesRelativeURLs() throws {
        let xml = """
        <addon id="repository.example" name="Example Repo" version="1.2.3" provider-name="Nova Test">
          <extension point="xbmc.addon.repository"><dir>
            <info>addons.xml</info><datadir>packages/</datadir>
          </dir></extension>
          <extension point="xbmc.addon.metadata">
            <summary lang="en_GB">Example packages</summary>
            <assets><icon>icon.png</icon></assets>
          </extension>
        </addon>
        """
        let source = URL(string: "https://example.com/repository/addon.xml")!
        let parsed = try KodiRepositoryClient.parse(data: Data(xml.utf8), sourceURL: source)
        let addon = try XCTUnwrap(parsed.packages.first)
        XCTAssertEqual(addon.id, "repository.example")
        XCTAssertEqual(addon.compatibility, .repository)
        XCTAssertEqual(addon.repositoryInfoURL?.absoluteString,
                       "https://example.com/repository/addons.xml")
        XCTAssertEqual(addon.repositoryDataURL?.absoluteString,
                       "https://example.com/repository/packages/")
    }

    func testExecutableVideoPluginIsNotMarkedNativeCompatible() throws {
        let xml = """
        <addons><addon id="plugin.video.example" name="Example" version="1.0.0">
          <extension point="xbmc.python.pluginsource" library="default.py">
            <provides>video</provides>
          </extension>
        </addon></addons>
        """
        let parsed = try KodiRepositoryClient.parse(
            data: Data(xml.utf8), sourceURL: URL(string: "https://example.com/addons.xml")!
        )
        XCTAssertEqual(parsed.packages.first?.compatibility, .kodiRuntimeRequired)
    }
}

final class KodiAdvancedCompatibilityTests: XCTestCase {
    func testNFOImportAndExportPreservePortableIdentity() throws {
        let source = """
        <?xml version="1.0" encoding="UTF-8"?>
        <movie><title>Arrival</title><year>2016</year>
        <uniqueid type="imdb">tt2543164</uniqueid><genre>Science Fiction</genre></movie>
        """
        let parsed = try KodiNFOCodec.parse(Data(source.utf8))
        XCTAssertEqual(parsed.title, "Arrival")
        XCTAssertEqual(parsed.year, 2016)
        XCTAssertEqual(parsed.uniqueIDs["imdb"], "tt2543164")

        let item = KodiNFOCodec.mediaItem(
            from: parsed,
            mediaURL: URL(fileURLWithPath: "/tmp/Arrival.mkv")
        )
        let exported = String(decoding: KodiNFOCodec.export(item), as: UTF8.self)
        XCTAssertTrue(exported.contains("<title>Arrival</title>"))
        XCTAssertTrue(exported.contains("tt2543164"))
    }

    func testSmartPlaylistEvaluatesLocally() {
        let item = MediaItem(
            title: "Arrival",
            sourceType: .smb,
            playbackURL: URL(fileURLWithPath: "/tmp/Arrival.mkv"),
            metadata: MediaMetadata(year: 2016),
            tags: ["Science Fiction"]
        )
        let playlist = NovaSmartPlaylist(
            name: "Modern science fiction",
            rules: [
                .init(field: .genre, operation: .contains, value: "science"),
                .init(field: .year, operation: .greaterThan, value: "2010")
            ]
        )
        XCTAssertTrue(playlist.matches(item))
    }

    func testDeclarativeProviderRejectsUnexpectedHostsAndBadChecksums() {
        let provider = NovaDeclarativeExtension(
            id: "subtitles.example", name: "Example", version: "1",
            kind: .subtitle,
            endpointTemplate: "https://api.example.com/subtitles?imdb={imdb}",
            allowedHosts: ["example.com"],
            sha256: String(repeating: "0", count: 64)
        )
        XCTAssertNotNil(provider.validatedURL(values: ["imdb": "tt2543164"]))
        XCTAssertFalse(provider.matchesDeclaredChecksum(Data("altered".utf8)))

        var escaped = provider
        escaped.endpointTemplate = "https://example.invalid/subtitles"
        XCTAssertNil(escaped.validatedURL(values: [:]))
    }
}
