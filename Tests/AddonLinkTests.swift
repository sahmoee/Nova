//
//  AddonLinkTests.swift
//  NovaTests
//
//  stremio:// addon links map to an HTTPS manifest and never carry credentials.
//

import XCTest
@testable import Nova

final class AddonLinkTests: XCTestCase {
    func testStremioLinkMapsToHTTPSManifest() throws {
        let link = try XCTUnwrap(URL(string: "stremio://addon.example.com/config123/manifest.json"))
        XCTAssertEqual(DeepLink.parse(link),
                       .installAddon(manifestURL: try XCTUnwrap(URL(string: "https://addon.example.com/config123/manifest.json"))))
    }

    func testStremioLinksWithoutManifestHostOrWithCredentialsAreRejected() throws {
        for raw in ["stremio://addon.example.com/catalog.json",
                    "stremio:///manifest.json",
                    "stremio://user:secret@addon.example.com/manifest.json"] {
            XCTAssertNil(DeepLink.parse(try XCTUnwrap(URL(string: raw))), raw)
        }
    }

    func testNovaLinksStillParse() throws {
        XCTAssertEqual(DeepLink.parse(try XCTUnwrap(URL(string: "nova://movies"))), .tab(.movies))
        XCTAssertEqual(DeepLink.parse(try XCTUnwrap(URL(string: "nova://series"))), .tab(.series))
    }
}
