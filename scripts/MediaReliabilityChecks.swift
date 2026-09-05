// Native host checks: compile with MediaReliabilityPolicy.swift and NetworkRetry.swift.
// The small transport error shape substitutes only the app's URLSession container;
// all retry scheduling and validation below runs the production implementations.
import Foundation

enum AppNetworking {
    enum RequestError: Error { case badStatus(Int, retryAfter: TimeInterval?) }
}

private actor AttemptCounter {
    var value = 0
    func next() -> Int { value += 1; return value }
}

@main
struct MediaReliabilityChecks {
    static func main() async throws {
        var count = 0
        func check(_ passed: Bool, _ name: String) {
            precondition(passed, name)
            count += 1
        }
        let now = Date(timeIntervalSince1970: 1_446_412_480)
        check(MediaReliabilityPolicy.retryAfter("12") == 12, "delta seconds")
        check(MediaReliabilityPolicy.retryAfter(" 0 \n") == 0, "zero and whitespace")
        check(MediaReliabilityPolicy.retryAfter("Wed, 21 Oct 2015 07:28:00 GMT", now: now) == 0, "past HTTP date")
        check(MediaReliabilityPolicy.retryAfter("Thu, 22 Oct 2015 07:28:00 GMT", now: Date(timeIntervalSince1970: 1_445_412_480)) == 86_400, "future HTTP date")
        for bad in ["", "-1", "nan", "inf", "1e999", "tomorrow"] {
            check(MediaReliabilityPolicy.retryAfter(bad) == nil, "reject invalid cooldown \(bad)")
        }
        check(MediaReliabilityPolicy.retryDelay(backoff: 1, serverMinimum: 10, remaining: 20, jitter: 0.8) == 10, "minimum cooldown is not jittered early")
        check(MediaReliabilityPolicy.retryDelay(backoff: 1, serverMinimum: 10, remaining: 5, jitter: 1) == nil, "cooldown beyond deadline stops")
        check(MediaReliabilityPolicy.retryDelay(backoff: 5, serverMinimum: nil, remaining: 5, jitter: 1) == nil, "no retry at deadline")
        check(MediaReliabilityPolicy.retryDelay(backoff: 1, serverMinimum: .nan, remaining: 10, jitter: 1) == 1, "invalid provider cooldown falls back")
        check(MediaReliabilityPolicy.retryDelay(backoff: .infinity, serverMinimum: nil, remaining: 10, jitter: 1) == nil, "infinite backoff rejected")
        check(MediaReliabilityPolicy.boundedInterval(.infinity, fallback: 20) == 20, "infinite timeout falls back")
        check(MediaReliabilityPolicy.boundedInterval(-1, fallback: 20) == 20, "negative timeout falls back")
        check(MediaReliabilityPolicy.boundedInterval(9_000, fallback: 20) == 300, "timeouts bounded")
        check(MediaReliabilityPolicy.validDuration(0) == nil, "zero duration unknown")
        check(MediaReliabilityPolicy.validDuration(.infinity) == nil, "infinite duration unknown")
        check(MediaReliabilityPolicy.validPosition(-5) == 0, "negative saved position repaired")
        check(MediaReliabilityPolicy.validPosition(.nan) == 0, "non-finite saved position repaired")
        check(MediaReliabilityPolicy.progress(position: 200, duration: 100) == 1, "overrun progress clamped")
        check(MediaReliabilityPolicy.progress(position: .nan, duration: 100) == 0, "invalid progress finite")
        check(MediaReliabilityPolicy.canResume(position: 98, duration: 100, isLive: false), "late pause resumes")
        check(!MediaReliabilityPolicy.canResume(position: 99.5, duration: 100, isLive: false), "completed checkpoint does not resume")
        check(!MediaReliabilityPolicy.canResume(position: 50, duration: 100, isLive: true), "live channel never resumes stale time")
        check(!MediaReliabilityPolicy.canResume(position: .infinity, duration: nil, isLive: false), "infinite resume rejected")
        check(MediaReliabilityPolicy.canResume(position: 50, duration: nil, isLive: false), "unknown duration retains checkpoint")
        check(!DownloadLifecycleState.complete.canPause, "completed files cannot pause")
        check(!DownloadLifecycleState.failed.canPause, "failed downloads cannot pause")
        check(DownloadLifecycleState.queued.canPause, "queued download can pause")
        check(DownloadLifecycleState.paused.canResume, "paused download resumes")
        check(!DownloadLifecycleState.downloading.canResume, "active download cannot start twice")
        check(!DownloadLifecycleState.complete.canRetry, "retry cannot delete a complete file")
        check(DownloadLifecycleState.failed.canRetry, "failed download retry available")
        check(MediaReliabilityPolicy.downloadBackoff(failureCount: 1) == 1, "first reconnect backed off")
        check(MediaReliabilityPolicy.downloadBackoff(failureCount: 5) == 16, "successive reconnects backed off")
        check(MediaReliabilityPolicy.downloadBackoff(failureCount: 6) == nil, "reconnect storm bounded")
        check(!MediaReliabilityPolicy.validDownloadResponse(status: 404, bytes: 100), "404 HTML is not a completed movie")
        check(!MediaReliabilityPolicy.validDownloadResponse(status: 200, bytes: 0), "empty download rejected")
        check(!MediaReliabilityPolicy.validDownloadResponse(status: 204, bytes: 10), "no-content response rejected")
        check(MediaReliabilityPolicy.validDownloadResponse(status: 206, bytes: 20), "resumed response accepted")
        let folder = URL(fileURLWithPath: "/tmp/Nova-OfflineMedia", isDirectory: true)
        check(MediaReliabilityPolicy.ownedFile(folder.appendingPathComponent("file.mp4"), in: folder), "owned media child accepted")
        check(!MediaReliabilityPolicy.ownedFile(folder.appendingPathComponent("../private-file.mp4"), in: folder), "path traversal rejected")
        check(!MediaReliabilityPolicy.ownedFile(URL(string: "https://example.invalid/video")!, in: folder), "remote deletion target rejected")
        let id = UUID()
        check(MediaReliabilityPolicy.ownedDownloadFile(folder.appendingPathComponent("\(id.uuidString).mp4"), id: id, in: folder), "exact owned download accepted")
        check(!MediaReliabilityPolicy.ownedDownloadFile(folder.appendingPathComponent("\(UUID().uuidString).mp4"), id: id, in: folder), "another transfer media cannot be removed")
        check(MediaReliabilityPolicy.resumeFilename("\(id.uuidString).resume", id: id) != nil, "owned resume name accepted")
        check(MediaReliabilityPolicy.resumeFilename("../secret", id: id) == nil, "resume traversal rejected")
        check(MediaReliabilityPolicy.resumeFilename("\(UUID().uuidString).resume", id: id) == nil, "another transfer resume rejected")
        let encoded = try JSONEncoder().encode(DownloadLifecycleState.complete)
        check(String(data: encoded, encoding: .utf8) == "\"complete\"", "download state persistence compatible")

        let transientCounter = AttemptCounter()
        let value: Int = try await withRetry(initialDelay: 0.001) {
            let attempt = await transientCounter.next()
            if attempt == 1 { throw URLError(.networkConnectionLost) }
            return attempt
        }
        check(value == 2, "real retry recovers a transient error")
        let permanentCounter = AttemptCounter()
        do {
            let _: Int = try await withRetry(initialDelay: 0.001) {
                _ = await permanentCounter.next(); throw URLError(.serverCertificateUntrusted)
            }
            preconditionFailure("certificate errors must fail")
        } catch { check(await permanentCounter.value == 1, "permanent TLS errors never retry") }
        let deadlineCounter = AttemptCounter()
        do {
            let _: Int = try await withRetry(initialDelay: 0.001, maxElapsed: 0.01) {
                _ = await deadlineCounter.next()
                throw AppNetworking.RequestError.badStatus(429, retryAfter: 30)
            }
            preconditionFailure("cooldown past deadline must fail")
        } catch { check(await deadlineCounter.value == 1, "real retry respects provider minimum before deadline") }
        let cappedCounter = AttemptCounter()
        do {
            let _: Int = try await withRetry(maxAttempts: 0, initialDelay: .nan) {
                _ = await cappedCounter.next(); throw URLError(.timedOut)
            }
            preconditionFailure("zero-attempt configuration must still fail safely")
        } catch { check(await cappedCounter.value == 1, "invalid retry configuration remains safe") }
        let cancelled = Task { () throws -> Int in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await withRetry { 42 }
        }
        do { _ = try await cancelled.value; preconditionFailure("cancelled request must stop") }
        catch is CancellationError { check(true, "pre-cancelled retry never begins") }
        let cancelledAfterResponse = Task { () throws -> Int in
            try await withRetry {
                withUnsafeCurrentTask { $0?.cancel() }
                return 42
            }
        }
        do { _ = try await cancelledAfterResponse.value; preconditionFailure("cancelled response must not publish success") }
        catch is CancellationError { check(true, "cancelled result never returns success") }
        print("Nova media reliability: \(count) checks passed.")
    }
}
