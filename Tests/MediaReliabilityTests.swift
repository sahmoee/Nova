import XCTest
@testable import Nova

final class MediaReliabilityTests: XCTestCase {
    func testServerCooldownCannotBeShortenedOrClippedToDeadline() {
        XCTAssertEqual(MediaReliabilityPolicy.retryDelay(backoff: 1, serverMinimum: 10, remaining: 20, jitter: 0.8), 10)
        XCTAssertNil(MediaReliabilityPolicy.retryDelay(backoff: 1, serverMinimum: 10, remaining: 5, jitter: 1))
        XCTAssertNil(MediaReliabilityPolicy.retryAfter("nan"))
        XCTAssertNil(MediaReliabilityPolicy.retryAfter("-5"))
    }

    func testRetryAfterHTTPDate() {
        let now = Date(timeIntervalSince1970: 1_445_412_480)
        XCTAssertEqual(MediaReliabilityPolicy.retryAfter("Thu, 22 Oct 2015 07:28:00 GMT", now: now), 86_400)
    }

    func testCompletedDownloadsCannotBeDestructivelyRetried() {
        XCTAssertFalse(OfflineDownload.State.complete.canPause)
        XCTAssertFalse(OfflineDownload.State.complete.canResume)
        XCTAssertFalse(OfflineDownload.State.complete.canRetry)
        XCTAssertTrue(OfflineDownload.State.failed.canRetry)
        XCTAssertTrue(OfflineDownload.State.paused.canResume)
    }

    func testMalformedDownloadResponsesAndRetryStormAreBounded() {
        XCTAssertFalse(MediaReliabilityPolicy.validDownloadResponse(status: 404, bytes: 500))
        XCTAssertFalse(MediaReliabilityPolicy.validDownloadResponse(status: 200, bytes: 0))
        XCTAssertTrue(MediaReliabilityPolicy.validDownloadResponse(status: 206, bytes: 500))
        XCTAssertNil(MediaReliabilityPolicy.downloadBackoff(failureCount: 6))
    }

    func testInvalidResumeAndProgressValuesCannotReachPlayer() {
        var item = MediaItem(title: "Fixture", sourceType: .directURL,
                             playbackURL: URL(string: "https://example.invalid/movie.mp4")!,
                             duration: .infinity, lastPlayedPosition: .nan, subtitleOffset: .infinity)
        XCTAssertNil(item.duration)
        XCTAssertEqual(item.lastPlayedPosition, 0)
        XCTAssertEqual(item.subtitleOffset, 0)
        XCTAssertNoThrow(try JSONEncoder().encode(item))
        item.lastPlayedPosition = .infinity
        XCTAssertFalse(item.hasResumePoint)
        XCTAssertEqual(item.progressFraction, 0)
    }

    func testLateProgressResumesButLiveContentNeverDoes() {
        var item = MediaItem(title: "Fixture", sourceType: .directURL,
                             playbackURL: URL(string: "https://example.invalid/movie.mp4")!,
                             duration: 100, lastPlayedPosition: 98)
        XCTAssertTrue(item.hasResumePoint)
        item.sourceType = .liveTV
        XCTAssertFalse(item.hasResumePoint)
    }

    func testResumeFilenameCannotEscapeOrUseAnotherDownload() {
        let id = UUID()
        XCTAssertNotNil(MediaReliabilityPolicy.resumeFilename("\(id.uuidString).resume", id: id))
        XCTAssertNil(MediaReliabilityPolicy.resumeFilename("../outside.resume", id: id))
        XCTAssertNil(MediaReliabilityPolicy.resumeFilename("\(UUID().uuidString).resume", id: id))
    }

    func testLegacyNegativePositionAndDurationRepairOnDecode() throws {
        let item = MediaItem(title: "Fixture", sourceType: .directURL,
                             playbackURL: URL(string: "https://example.invalid/movie.mp4")!)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
        object["duration"] = -10
        object["lastPlayedPosition"] = -50
        let repaired = try JSONDecoder().decode(MediaItem.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(repaired.duration)
        XCTAssertEqual(repaired.lastPlayedPosition, 0)
        XCTAssertEqual(repaired.id, item.id)
        XCTAssertEqual(repaired.contentKey, item.contentKey)
    }
}
