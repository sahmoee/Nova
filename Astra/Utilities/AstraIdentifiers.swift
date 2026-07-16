//
//  AstraIdentifiers.swift
//  Astra
//
//  The single source of truth for identifiers that MUST agree across the app,
//  widgets, Top Shelf extension, entitlements, and the project configuration.
//  Repeating these as scattered string literals is how they silently drift
//  (e.g. the App Group mismatch that broke the shared container). Prefer these
//  constants over inline strings; validate_astra_config.sh checks the build-time
//  values against the same source of truth.
//

import Foundation

enum AstraIdentifiers {

    // MARK: - App Group (shared container: app <-> widgets <-> Top Shelf)
    /// The ONE App Group. Must match every target's .entitlements exactly.
    static let appGroup = "group.astra.ios"

    // MARK: - Bundle identifiers (three intentional per-target IDs)
    static let bundleIDiOS = "com.astra.app.ios"
    static let bundleIDWidgets = "com.astra.app.ios.widgets"
    static let bundleIDtvOS = "com.astra.app.tvos"

    // MARK: - Team
    static let developmentTeam = "5DV5N49VG8"

    // MARK: - Deep-link URL scheme  (astra://…)
    static let urlScheme = "astra"

    // MARK: - Logging / signposts subsystem
    static let subsystem = "com.astra.app"

    // MARK: - Keychain service
    static let keychainService = "com.astra.app.secrets"

    // MARK: - Worker endpoints (paths appended to the configured Worker base URL)
    enum WorkerPath {
        static let titles = "titles"
        static let filter = "filter"
        static let troubleshoot = "troubleshoot"
        static let shareCreate = "share/create"
        static let shareFetch = "share/fetch"
        static let diag = "diag"
        static let health = "health"
    }

    /// The shared App Group container URL, or nil if the entitlement is missing.
    static var appGroupContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }
}
