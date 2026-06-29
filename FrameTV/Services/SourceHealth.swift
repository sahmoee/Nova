//
//  SourceHealth.swift
//  FrameTV
//
//  Centralizes the connection/health status of each external source (Real-Debrid,
//  TMDB, Trakt, addons, SMB) so the Sources screen, Settings, and Home can all show
//  a consistent at-a-glance status. Status is derived from stored credentials and
//  configuration; it does not perform network calls (use SMBChecker for a live test).
//

import Foundation

/// A single source's health line for display.
struct SourceHealthItem: Identifiable {
    let id: String
    let name: String
    let systemImage: String
    let status: SourceStatus
    /// Optional extra detail, e.g. "5 installed".
    var detail: String? = nil
}

@MainActor
enum SourceHealth {

    /// Real-Debrid: connected when a token is stored.
    static func realDebrid() -> SourceHealthItem {
        let connected = KeychainStore.shared.realDebridToken != nil
        return SourceHealthItem(
            id: "realdebrid",
            name: "Real-Debrid",
            systemImage: "arrow.down.circle",
            status: connected ? .connected : .notConfigured
        )
    }

    /// TMDB: needs an API key for posters/metadata. Without it, artwork is missing.
    static func tmdb() -> SourceHealthItem {
        let hasKey = AppConfig.shared.tmdbKey?.isEmpty == false
        return SourceHealthItem(
            id: "tmdb",
            name: "TMDB",
            systemImage: "photo.on.rectangle",
            status: hasKey ? .connected : .error("Missing API key"),
            detail: hasKey ? nil : "Posters and details won't load"
        )
    }

    /// Trakt: connected when an access token is present.
    static func trakt() -> SourceHealthItem {
        let authed = AppConfig.shared.value(for: .traktAccessToken)?.isEmpty == false
        return SourceHealthItem(
            id: "trakt",
            name: "Trakt",
            systemImage: "checkmark.seal",
            status: authed ? .connected : .notConfigured
        )
    }

    /// Addons: connected when at least one stream addon is installed.
    static func addons(_ store: AddonStore) -> SourceHealthItem {
        let count = store.streamAddons.count
        return SourceHealthItem(
            id: "addons",
            name: "Addons",
            systemImage: "puzzlepiece.extension",
            status: count > 0 ? .connected : .notConfigured,
            detail: count > 0 ? "\(count) installed" : nil
        )
    }

    /// SMB: best-effort from stored shares. A real connection test is in SMBChecker.
    static func smb(shareCount: Int) -> SourceHealthItem {
        SourceHealthItem(
            id: "smb",
            name: "SMB Shares",
            systemImage: "externaldrive.connected.to.line.below",
            status: shareCount > 0 ? .connected : .notConfigured,
            detail: shareCount > 0 ? "\(shareCount) configured" : nil
        )
    }

    /// All sources in a stable display order. Pass the env-provided stores.
    static func all(addonStore: AddonStore, smbShareCount: Int) -> [SourceHealthItem] {
        [
            realDebrid(),
            tmdb(),
            trakt(),
            addons(addonStore),
            smb(shareCount: smbShareCount)
        ]
    }

    /// A compact summary for a header chip, e.g. "2 need attention".
    static func summary(_ items: [SourceHealthItem]) -> (needsAttention: Int, connected: Int) {
        var attention = 0, connected = 0
        for i in items {
            switch i.status {
            case .connected: connected += 1
            case .error, .disconnected, .notConfigured: attention += 1
            }
        }
        return (attention, connected)
    }
}
