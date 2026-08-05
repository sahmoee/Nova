//
//  DiskJSONCacheTests.swift
//  NovaTests
//
//  Round-trip, expiry, and prefix-isolation tests for the generic disk cache.
//

import XCTest
@testable import Nova

final class DiskJSONCacheTests: XCTestCase {

    func testRoundTrip() async {
        let cache = DiskJSONCache<[String]>(folder: "TestCacheA",
                                            filePrefix: "t_", maxAge: 60)
        await cache.clear()
        await cache.store(["a", "b", "c"], for: "key1")
        let out = await cache.value(for: "key1")
        XCTAssertEqual(out, ["a", "b", "c"])
        await cache.clear()
    }

    func testMissingKeyReturnsNil() async {
        let cache = DiskJSONCache<[String]>(folder: "TestCacheB",
                                            filePrefix: "t_", maxAge: 60)
        await cache.clear()
        let out = await cache.value(for: "nope")
        XCTAssertNil(out)
    }

    func testExpiredEntryReturnsNil() async {
        let cache = DiskJSONCache<Int>(folder: "TestCacheC",
                                       filePrefix: "t_", maxAge: 0)
        await cache.store(42, for: "old")
        // maxAge 0 means any stored entry is immediately stale.
        try? await Task.sleep(for: .milliseconds(50))
        let out = await cache.value(for: "old")
        XCTAssertNil(out)
        await cache.clear()
    }

    func testClearRemovesOnlyOwnPrefix() async {
        let a = DiskJSONCache<Int>(folder: "TestCacheD", filePrefix: "a_", maxAge: 60)
        let b = DiskJSONCache<Int>(folder: "TestCacheD", filePrefix: "b_", maxAge: 60)
        await a.store(1, for: "x")
        await b.store(2, for: "x")
        await a.clear()
        let av = await a.value(for: "x")
        let bv = await b.value(for: "x")
        XCTAssertNil(av)
        XCTAssertEqual(bv, 2)
        await b.clear()
    }
}
