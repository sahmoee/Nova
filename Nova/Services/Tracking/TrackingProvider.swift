//
//  TrackingProvider.swift
//  Nova
//
//  A backend-agnostic abstraction over watch-tracking services (Trakt, SIMKL,
//  TMDB account, …). Each service is optional: the user may connect any number of
//  them. `TrackingHub` fans writes (scrobble/sync) out to every connected provider
//  and merges reads (watchlist/trending), so the rest of the app never depends on a
//  single service. Add a new tracker by conforming to `TrackingProvider` and adding
//  it to the hub in AppEnvironment.
//
//  `ConnectionStatus` and `ScrobbleAction` are defined in TraktClient.swift and
//  shared across all providers.
//

import Foundation

/// Stable identifier for each supported tracker.
enum TrackerID: String, CaseIterable, Codable, Sendable {
    case trakt
    case simkl
    case tmdb
}

/// A watch-tracking backend. All members are async so actor-backed clients can
/// conform directly. Providers are optional and independent of one another.
protocol TrackingProvider: Sendable {
    nonisolated var trackerID: TrackerID { get }
    nonisolated var displayName: String { get }

    /// True when the service has the credentials it needs to attempt a connection.
    func configured() async -> Bool
    /// True when a usable access token is stored.
    func authenticated() async -> Bool
    /// A live, validated status (actually contacts the service).
    func validateConnection() async -> ConnectionStatus
    /// Clears stored tokens for this provider.
    func signOut() async
    /// Renews the access token if needed; returns whether one is usable afterward.
    @discardableResult func refreshIfNeeded() async -> Bool

    /// The user's watchlist / plan-to-watch as catalog items.
    func watchlist() async throws -> [CatalogItem]
    /// Trending shows for a discovery row (may be empty if unsupported).
    func trendingShows() async throws -> [CatalogItem]
    /// Best-effort pull to refresh local state; never throws.
    func syncNow() async

    /// Reports playback. Providers map this to their own model (Trakt scrobbles in
    /// real time; SIMKL sets a watching status on start and writes history on stop;
    /// TMDB has no watched state and ignores it). Returns whether anything was sent.
    @discardableResult
    func scrobble(action: ScrobbleAction,
                  contentID: ContentID,
                  episode: EpisodeRef?,
                  progress: Double) async -> Bool
}

extension TrackingProvider {
    // Sensible defaults so a provider can omit what it doesn't support.
    func trendingShows() async throws -> [CatalogItem] { [] }
    func syncNow() async { _ = await refreshIfNeeded() }
}

/// Aggregates every configured tracker. Writes fan out to all connected providers;
/// reads merge and de-duplicate across them.
final class TrackingHub: Sendable {
    let providers: [any TrackingProvider]

    init(_ providers: [any TrackingProvider]) {
        self.providers = providers
    }

    /// Providers that currently have a usable token.
    func connectedProviders() async -> [any TrackingProvider] {
        var out: [any TrackingProvider] = []
        for p in providers where await p.authenticated() { out.append(p) }
        return out
    }

    /// True if at least one tracker is connected.
    func anyConnected() async -> Bool {
        for p in providers where await p.authenticated() { return true }
        return false
    }

    /// Merged watchlist across all connected trackers, de-duplicated by content key.
    func watchlist() async -> [CatalogItem] {
        var seen = Set<String>()
        var merged: [CatalogItem] = []
        for p in await connectedProviders() {
            guard let items = try? await p.watchlist() else { continue }
            for item in items where seen.insert(item.contentID.stableKey).inserted {
                merged.append(item)
            }
        }
        return merged
    }

    /// Merged trending shows across trackers that support it.
    func trendingShows() async -> [CatalogItem] {
        var seen = Set<String>()
        var merged: [CatalogItem] = []
        for p in providers {
            guard let items = try? await p.trendingShows(), !items.isEmpty else { continue }
            for item in items where seen.insert(item.contentID.stableKey).inserted {
                merged.append(item)
            }
        }
        return merged
    }

    /// Fan a scrobble out to every connected provider. Returns true if any accepted.
    @discardableResult
    func scrobble(action: ScrobbleAction,
                  contentID: ContentID,
                  episode: EpisodeRef?,
                  progress: Double) async -> Bool {
        var any = false
        for p in await connectedProviders() {
            if await p.scrobble(action: action, contentID: contentID,
                                episode: episode, progress: progress) { any = true }
        }
        return any
    }

    /// Refresh + pull on every connected provider.
    func syncNow() async {
        for p in await connectedProviders() { await p.syncNow() }
    }

    /// Refresh tokens on every provider that has one (e.g. after a backup restore).
    func refreshAll() async {
        for p in providers { _ = await p.refreshIfNeeded() }
    }

    /// Look up a provider instance by id (for per-service settings screens).
    func provider(_ id: TrackerID) -> (any TrackingProvider)? {
        providers.first { $0.trackerID == id }
    }
}

// MARK: - Trakt conformance (Trakt stays optional, now one provider among several)

extension TraktClient: TrackingProvider {
    nonisolated var trackerID: TrackerID { .trakt }
    nonisolated var displayName: String { "Trakt" }
    func configured() async -> Bool { isConfigured }
    func authenticated() async -> Bool { isAuthenticated }
    // validateConnection, signOut, refreshIfNeeded, watchlist, trendingShows,
    // syncNow, and scrobble already match the protocol.
}
