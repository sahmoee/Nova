//
//  NetworkRetry.swift
//  Nova
//
//  Small helpers for resilient networking:
//    - `withRetry` runs an async throwing operation with a bounded number of
//      retries and exponential backoff, for transient failures on flaky networks.
//    - `NovaLog` is a thin os.Logger wrapper so failures are diagnosable instead of
//      being silently swallowed by `try?`.
//

import Foundation
import os

enum NovaLog {
    static let network = Logger(subsystem: "com.nova.app", category: "network")
    static let catalog = Logger(subsystem: "com.nova.app", category: "catalog")
    static let player  = Logger(subsystem: "com.nova.app", category: "player")
    static let sync    = Logger(subsystem: "com.nova.app", category: "sync")
}

/// Runs `operation`, retrying up to `maxAttempts` times with jittered exponential
/// backoff on transient failures. Improvements over a naive retry:
///  • Jitter — randomizes each delay to avoid synchronized retry storms.
///  • Cancellation-aware — a cancelled task stops immediately (Task.sleep throws).
///  • HTTP transient statuses — 408/425/429/500/502/503/504 are retried, others fail fast.
///  • Retry-After — honored when the server provides it (via AppNetworking.RequestError).
///  • Total deadline — gives up once `maxElapsed` seconds have passed, regardless of attempts.
func withRetry<T>(
    maxAttempts: Int = 3,
    initialDelay: TimeInterval = 0.5,
    maxDelay: TimeInterval = 10,
    maxElapsed: TimeInterval = 30,
    operation: @Sendable () async throws -> T
) async throws -> T {
    let clock = ContinuousClock()
    let start = clock.now
    let elapsedLimit = MediaReliabilityPolicy.boundedInterval(maxElapsed, fallback: 30)
    let delayLimit = MediaReliabilityPolicy.boundedInterval(maxDelay, fallback: 10)
    let attemptLimit = min(max(maxAttempts, 1), 10)
    var attempt = 0
    var delay = MediaReliabilityPolicy.boundedInterval(initialDelay, fallback: 0.5, maximum: delayLimit)
    while true {
        try Task.checkCancellation()
        do {
            let result = try await operation()
            try Task.checkCancellation()
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            attempt += 1
            let duration = start.duration(to: clock.now).components
            let elapsed = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
            guard attempt < attemptLimit, isTransient(error), elapsed < elapsedLimit else { throw error }

            // Honor Retry-After if the server sent one; otherwise jittered backoff.
            guard let sleepFor = MediaReliabilityPolicy.retryDelay(
                backoff: min(delay, delayLimit), serverMinimum: retryAfter(from: error),
                remaining: elapsedLimit - elapsed, jitter: Double.random(in: 0.8...1.2)) else { throw error }
            try await Task.sleep(for: .seconds(sleepFor))
            guard start.duration(to: clock.now) < .seconds(elapsedLimit) else { throw error }
            delay = min(delay * 2, delayLimit)
        }
    }
}

/// Transient HTTP status codes worth retrying.
private let transientStatuses: Set<Int> = [408, 425, 429, 500, 502, 503, 504]

private func retryAfter(from error: Error) -> TimeInterval? {
    if case let AppNetworking.RequestError.badStatus(_, retryAfter) = error { return retryAfter }
    return nil
}

private func isTransient(_ error: Error) -> Bool {
    if let urlError = error as? URLError {
        switch urlError.code {
        case .timedOut, .cannotConnectToHost, .networkConnectionLost,
             .notConnectedToInternet, .dnsLookupFailed, .resourceUnavailable:
            return true
        default:
            return false
        }
    }
    if case let AppNetworking.RequestError.badStatus(code, _) = error {
        return transientStatuses.contains(code)
    }
    return false
}
