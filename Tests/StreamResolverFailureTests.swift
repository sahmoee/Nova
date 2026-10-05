import XCTest
@testable import Nova

/// Real-Debrid failure paths: each must surface a specific error and clean up the
/// torrent it added, instead of the generic "no playable link" after minutes of polling.
final class StreamResolverFailureTests: XCTestCase {
    private let infoHash = String(repeating: "a", count: 40)

    override func tearDown() {
        StubRD.reset()
        super.tearDown()
    }

    private func resolver() -> StreamResolver {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubRD.self]
        let client = RealDebridClient(session: URLSession(configuration: config), tokenProvider: { "test-token" })
        return StreamResolver(realDebrid: client)
    }

    func testStreamWithoutLinkOrHashIsUnsupported() async {
        let stream = StreamOption(addonName: "Test", rawTitle: "Configure addon")
        do {
            _ = try await resolver().resolve(stream, hasDebridToken: true)
            XCTFail("Expected failure")
        } catch let error as StreamResolveError {
            guard case .unsupportedStream = error else { return XCTFail("Got \(error)") }
            XCTAssertFalse(error.isSpecific)
        } catch { XCTFail("Got \(error)") }
    }

    func testDeadTorrentFailsFastAndIsDeleted() async throws {
        StubRD.torrentStatus = "magnet_error"
        let stream = StreamOption(addonName: "Test", rawTitle: "Movie", infoHash: infoHash)
        let started = Date()
        do {
            _ = try await resolver().resolve(stream, hasDebridToken: true)
            XCTFail("Expected failure")
        } catch let error as StreamResolveError {
            guard case .torrentFailed(let status) = error else { return XCTFail("Got \(error)") }
            XCTAssertEqual(status, "magnet_error")
            XCTAssertTrue(error.isSpecific)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        // Cleanup runs detached; give it a moment.
        for _ in 0..<20 where !StubRD.deleted { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(StubRD.deleted)
    }
}

/// Minimal Real-Debrid stand-in: addMagnet succeeds, info reports `torrentStatus`.
private final class StubRD: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var torrentStatus = "downloaded"
    nonisolated(unsafe) static var deleted = false
    static func reset() { torrentStatus = "downloaded"; deleted = false }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let path = request.url?.path ?? ""
        var status = 200
        var body = "{}"
        if path.hasSuffix("/torrents/addMagnet") {
            status = 201; body = #"{"id":"T1","uri":"x"}"#
        } else if path.contains("/torrents/info/") {
            body = #"{"id":"T1","status":"\#(Self.torrentStatus)","files":[],"links":[]}"#
        } else if path.contains("/torrents/delete/") {
            Self.deleted = true; status = 204; body = ""
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
