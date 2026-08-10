//
//  NovaIdentifiers.swift
//  Nova
//
//  The single source of truth for identifiers that MUST agree across the app,
//  widgets, Top Shelf extension, entitlements, and the project configuration.
//  Repeating these as scattered string literals is how they silently drift
//  (e.g. the App Group mismatch that broke the shared container). Prefer these
//  constants over inline strings; validate_nova_config.sh checks the build-time
//  values against the same source of truth.
//

import Foundation

enum NovaIdentifiers {

    // MARK: - App Group (shared container: app <-> widgets <-> Top Shelf)
    /// Shared container identity for Nova. Must match the App Group enabled on the
    /// app, widgets, and tvOS entitlements.
    static let appGroup = "group.nova.ios"

    // MARK: - App Store identities
    // Bundle identifiers are permanent technical identities, not display names.
    static let bundleIDiOS = "com.nova.app.ios"
    static let bundleIDWidgets = "com.nova.app.ios.widgets"
    static let bundleIDtvOS = "com.nova.app.tvos"

    // MARK: - Team
    static let developmentTeam = "5DV5N49VG8"

    // MARK: - Deep-link URL scheme  (nova://…)
    static let urlScheme = "nova"

    // MARK: - Logging / signposts subsystem
    static let subsystem = "com.nova.app"

    // MARK: - Keychain service
    static let keychainService = "com.nova.app.secrets"

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
