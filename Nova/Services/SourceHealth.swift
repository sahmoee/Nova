//
//  SourceHealth.swift
//  Nova
//
//  Centralizes the connection/health status of each external source (Real-Debrid,
//  TMDB, Trakt, addons, SMB) so the Sources screen, Settings, and Home can all show
//  a consistent at-a-glance status. Status is derived from stored credentials and
//  configuration; it does not perform network calls (use SMBChecker for a live test).
//

import Foundation
import Combine

/// A single source's health line for display.
struct SourceHealthItem: Identifiable {
    let id: String
    let name: String
    let systemImage: String
    let status: SourceStatus
    /// Optional extra detail, e.g. "5 installed".
    var detail: String? = nil
    var lastChecked: Date? = nil
}

@MainActor
final class SourceHealthMonitor: ObservableObject {
    @Published private(set) var items: [SourceHealthItem] = []
    @Published private(set) var isChecking = false

    func refresh(environment env: AppEnvironment, smbShares: [SMBShare]) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        var results: [SourceHealthItem] = []

        if KeychainStore.shared.realDebridToken == nil {
            results.append(SourceHealth.realDebrid())
        } else {
            do {
                _ = try await env.realDebrid.validateToken()
                results.append(.init(id: "realdebrid", name: "Real-Debrid",
                                     systemImage: "arrow.down.circle", status: .connected,
                                     detail: "Account verified", lastChecked: Date()))
            } catch {
                results.append(.init(id: "realdebrid", name: "Real-Debrid",
                                     systemImage: "arrow.down.circle",
                                     status: .error(error.localizedDescription),
                                     detail: "Account check failed", lastChecked: Date()))
            }
        }

        if AppConfig.shared.tmdbKey?.isEmpty != false {
            results.append(SourceHealth.tmdb())
        } else {
            do {
                _ = try await env.tmdb.trendingMovies()
                results.append(.init(id: "tmdb", name: "TMDB", systemImage: "photo.on.rectangle",
                                     status: .connected, detail: "Catalog verified", lastChecked: Date()))
            } catch {
                results.append(.init(id: "tmdb", name: "TMDB", systemImage: "photo.on.rectangle",
                                     status: .error(error.localizedDescription),
                                     detail: "Catalog check failed", lastChecked: Date()))
            }
        }

        let traktStatus = await env.trakt.validateConnection()
        let mappedTrakt: SourceStatus
        switch traktStatus {
        case .connected: mappedTrakt = .connected
        case .notConfigured: mappedTrakt = .notConfigured
        case .disconnected: mappedTrakt = .disconnected
        case .expired: mappedTrakt = .error("Session expired")
        case .error(let message): mappedTrakt = .error(message)
        }
        results.append(.init(id: "trakt", name: "Trakt", systemImage: "checkmark.seal",
                             status: mappedTrakt, detail: "Account endpoint checked", lastChecked: Date()))

        if env.addonStore.enabled.isEmpty {
            results.append(SourceHealth.addons(env.addonStore))
        } else {
            let health = await env.addonStore.checkHealth()
            let failures = health.values.filter {
                if case .broken = $0 { return true }
                return false
            }.count
            results.append(.init(id: "addons", name: "Addons",
                                 systemImage: "puzzlepiece.extension",
                                 status: failures == 0 ? .connected : .error("\(failures) failing"),
                                 detail: "Manifest and resource endpoints checked", lastChecked: Date()))
        }

        if let share = smbShares.first {
            do {
                try await env.smb.connect(to: share)
                _ = try await env.smb.listDirectory(share.path ?? "/")
                results.append(.init(id: "smb", name: "SMB Shares",
                                     systemImage: "externaldrive.connected.to.line.below",
                                     status: .connected, detail: "\(smbShares.count) configured · browse verified",
                                     lastChecked: Date()))
            } catch {
                results.append(.init(id: "smb", name: "SMB Shares",
                                     systemImage: "externaldrive.connected.to.line.below",
                                     status: .error(error.localizedDescription),
                                     detail: "Server browse failed", lastChecked: Date()))
            }
        } else {
            results.append(SourceHealth.smb(shareCount: 0))
        }
        items = results
    }
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
