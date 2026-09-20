// QAConfiguration.swift
// ─────────────────────────────────────────────────────────────────────────────
// Shared QACore — app-agnostic. Drop this folder into any of the seven apps.
//
// Every app calls QA.configure(...) once, before the first view appears, with
// its own source identifier, worker URL, and authorization hook.  Everything
// else in QACore reads from QA.config at runtime rather than hard-coding
// Stocked values.
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import UIKit

// MARK: - Configuration

public struct QAConfiguration: Sendable {
    /// The `source` tag that rides every report envelope — "stocked-app",
    /// "atlas-app", "nova-app", etc. Must match the SOURCES allowlist in the
    /// UnifiedWorker qa.js.
    public var source: String

    /// Ticket number prefix — "STK", "ATL", "NOV", "LD", "SSH", "STD", "APL".
    public var ticketPrefix: String

    /// Scheme + host for the worker, no trailing slash — "https://api.example.com".
    public var workerBaseURL: String

    /// Stamp auth headers (shared key, bearer token, etc.) onto a QA request.
    /// Called before every POST to the worker.
    public var authorizeRequest: @Sendable (inout URLRequest) -> Void

    /// Current app version string (CFBundleShortVersionString).
    public var version: String

    /// Numeric build number (CFBundleVersion as Int).
    public var buildNumber: Int

    /// Returns true when the device has network access. Default returns true;
    /// swap in your app's ConnectivityMonitor for a real check.
    public var isOnline: @Sendable () -> Bool

    /// Human-readable app name shown in the QA hub title.
    public var appName: String

    nonisolated public init(
        source: String,
        ticketPrefix: String,
        workerBaseURL: String,
        appName: String,
        version: String,
        buildNumber: Int,
        authorizeRequest: @escaping @Sendable (inout URLRequest) -> Void,
        isOnline: @escaping @Sendable () -> Bool = { true }
    ) {
        self.source = source
        self.ticketPrefix = ticketPrefix
        self.workerBaseURL = workerBaseURL
        self.appName = appName
        self.version = version
        self.buildNumber = buildNumber
        self.authorizeRequest = authorizeRequest
        self.isOnline = isOnline
    }
}

// MARK: - Namespace

/// `QA.configure(...)` once on launch; every other QACore type reads `QA.config`.
@MainActor
public enum QA {
    private(set) nonisolated(unsafe) static var config = QAConfiguration(
        source: "unknown-app",
        ticketPrefix: "QA",
        workerBaseURL: "",
        appName: "App",
        version: "?",
        buildNumber: 0,
        authorizeRequest: { _ in }
    )

    /// Call once, before any view appears — typically in your `@main` struct's
    /// `init()` or in `AppDelegate.application(_:didFinishLaunchingWithOptions:)`.
    public static func configure(_ configuration: QAConfiguration) {
        config = configuration
        // Kick the recorder into lazy-init territory so `isAvailable` is settled.
        _ = QARecorder.shared
    }
}
