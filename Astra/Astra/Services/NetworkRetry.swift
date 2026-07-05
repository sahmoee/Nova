//
//  NetworkRetry.swift
//  Astra
//
//  Small helpers for resilient networking:
//    - `withRetry` runs an async throwing operation with a bounded number of
//      retries and exponential backoff, for transient failures on flaky networks.
//    - `FrameLog` is a thin os.Logger wrapper so failures are diagnosable instead of
//      being silently swallowed by `try?`.
//

import Foundation
import os

enum FrameLog {
    static let network = Logger(subsystem: "com.astra.app", category: "network")
    static let catalog = Logger(subsystem: "com.astra.app", category: "catalog")
    static let player  = Logger(subsystem: "com.astra.app", category: "player")
    static let sync    = Logger(subsystem: "com.astra.app", category: "sync")
}

/// Runs `operation`, retrying up to `maxAttempts` times with exponential backoff
/// when it throws. Only retries transient-looking errors (URLError timeouts,
/// connection loss, etc.); other errors fail fast.
func withRetry<T>(
    maxAttempts: Int = 3,
    initialDelay: TimeInterval = 0.5,
    operation: @Sendable () async throws -> T
) async throws -> T {
    var attempt = 0
    var delay = initialDelay
    while true {
        do {
            return try await operation()
        } catch {
            attempt += 1
            guard attempt < maxAttempts, isTransient(error) else { throw error }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            delay *= 2
        }
    }
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
    return false
}
