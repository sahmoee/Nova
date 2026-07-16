//
//  NetworkRetry.swift
//  Astra
//
//  Small helpers for resilient networking:
//    - `withRetry` runs an async throwing operation with a bounded number of
//      retries and exponential backoff, for transient failures on flaky networks.
//    - `AstraLog` is a thin os.Logger wrapper so failures are diagnosable instead of
//      being silently swallowed by `try?`.
//

import Foundation
import os

enum AstraLog {
    static let network = Logger(subsystem: "com.astra.app", category: "network")
    static let catalog = Logger(subsystem: "com.astra.app", category: "catalog")
    static let player  = Logger(subsystem: "com.astra.app", category: "player")
    static let sync    = Logger(subsystem: "com.astra.app", category: "sync")
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
    let start = Date()
    var attempt = 0
    var delay = initialDelay
    while true {
        try Task.checkCancellation()
        do {
            return try await operation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            attempt += 1
            let elapsed = Date().timeIntervalSince(start)
            guard attempt < maxAttempts, isTransient(error), elapsed < maxElapsed else { throw error }

            // Honor Retry-After if the server sent one; otherwise jittered backoff.
            let base = retryAfter(from: error) ?? min(delay, maxDelay)
            let jittered = base * Double.random(in: 0.8...1.2)
            // Don't sleep past the deadline.
            let remaining = maxElapsed - elapsed
            let sleepFor = max(0, min(jittered, remaining))
            if sleepFor <= 0 { throw error }
            try await Task.sleep(nanoseconds: UInt64(sleepFor * 1_000_000_000))
            delay = min(delay * 2, maxDelay)
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
