//
//  AddonStore.swift
//  Nova
//
//  Persists the user's installed addons to a local JSON file and exposes them to
//  the rest of the app. Seeds Stremio's public Cinemeta metadata addon on first
//  run so series/episode metadata works out of the box, plus any addon URLs from
//  the optional config file.
//

import Foundation
import Combine

private actor AddonDiskPersistence {
    let fileURL: URL

    init(fileURL: URL) { self.fileURL = fileURL }

    func write(_ addons: [InstalledAddon]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(addons)
        try data.write(to: fileURL, options: [.atomic])
        return data
    }
}

@MainActor
final class AddonStore: ObservableObject {

    @Published private(set) var addons: [InstalledAddon] = []
    /// Last health-check response time per addon, in milliseconds.
    @Published private(set) var lastPingMS: [UUID: Int] = [:]
    @Published private(set) var lastHealthCheck: [UUID: Date] = [:]
    /// Fresh manifests advertised by installed add-ons. The installed version is
    /// left untouched until the user explicitly applies the update.
    @Published private(set) var availableUpdates: [UUID: InstalledAddon] = [:]
    @Published private(set) var lastPersistenceError: String?
    @Published private(set) var lastRemoved: InstalledAddon?
    private var lastRemovedSecret: String?

    private let fileURL: URL
    private let disk: AddonDiskPersistence
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let client = StremioAddonClient()
    private var cancellables = Set<AnyCancellable>()

    /// iCloud KVS key for the addon list.
    private static let cloudKey = "cloud.addons"

    /// Stremio's official metadata addon (public, no config). Provides meta +
    /// catalogs keyed by IMDB id — not streams.
    static let cinemetaManifest = URL(string: "https://v3-cinemeta.strem.io/manifest.json")!

    init(filename: String = "addons.json") {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        fileURL = support.appendingPathComponent(filename)
        disk = AddonDiskPersistence(fileURL: fileURL)
        encoder.outputFormatting = [.prettyPrinted]
        load()
        migrateSensitiveURLsToKeychain()
        mergeFromCloud()

        // Sync when another device changes the addon list.
        CloudSync.shared.externalChange
            .receive(on: RunLoop.main)
            .sink { [weak self] keys in
                if keys.contains(Self.cloudKey) { self?.mergeFromCloud() }
            }
            .store(in: &cancellables)

        // Reload the installed addons after a backup restore writes the new list to
        // disk; otherwise this store keeps the set it read at launch.
        NotificationCenter.default.addObserver(
            forName: .novaBackupRestored, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reload() }
        }
    }

    /// Re-reads the installed addons from disk and iCloud. Used after a restore.
    func reload() {
        load()
        mergeFromCloud()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        addons = (try? decoder.decode([InstalledAddon].self, from: data)) ?? []
    }

    private func persist() {
        let snapshot = addons.map { addon -> InstalledAddon in
            var safe = addon
            safe.manifestURL = addon.redactedManifestURL
            return safe
        }
        Task {
            do {
                let data = try await disk.write(snapshot)
                CloudSync.shared.setData(data, forKey: Self.cloudKey)
                lastPersistenceError = nil
            } catch {
                lastPersistenceError = error.localizedDescription
                NovaLog.sync.error("Add-on persistence failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Pulls the iCloud addon list if it exists and differs from local.
    private func mergeFromCloud() {
        guard let data = CloudSync.shared.data(forKey: Self.cloudKey),
              let cloudAddons = try? decoder.decode([InstalledAddon].self, from: data) else { return }
        // Last-write-wins by adopting the cloud set when it's non-empty.
        // FIX: enforce the documented "non-empty" condition. An empty cloud list
        // (e.g. pushed by a fresh device before seeding) previously wiped every
        // locally installed addon.
        guard !cloudAddons.isEmpty else { return }
        if cloudAddons != addons {
            addons = cloudAddons
            // Persist locally without re-pushing identical data to the cloud.
            let snapshot = addons
            Task {
                do { _ = try await disk.write(snapshot) }
                catch { lastPersistenceError = error.localizedDescription }
            }
        }
    }

    /// One-time migration for older builds that persisted configured transport URLs
    /// directly in addons.json/iCloud. The complete value moves to Keychain and the
    /// in-memory record is redacted before the next persistence pass.
    private func migrateSensitiveURLsToKeychain() {
        var changed = false
        for index in addons.indices where addons[index].manifestURLContainsSensitiveConfiguration {
            let fullURL = addons[index].manifestURL
            do {
                try KeychainStore.shared.set(fullURL.absoluteString,
                                             for: addons[index].secureManifestAccount)
                addons[index].manifestURL = addons[index].redactedManifestURL
                changed = true
            } catch {
                lastPersistenceError = error.localizedDescription
            }
        }
        if changed { persist() }
    }

    // MARK: - Queries

    /// Enabled addons, unless Safe Mode is on (in which case none are active, so a
    /// misbehaving addon can't stall catalogs, streams, or subtitles).
    var enabled: [InstalledAddon] {
        SafeMode.isOn ? [] : addons.filter { $0.isEnabled }.map(resolved)
    }
    var streamAddons: [InstalledAddon] { enabled.filter { $0.supports(resource: "stream") } }
    var subtitleAddons: [InstalledAddon] { enabled.filter { $0.supports(resource: "subtitles") } }
    var metaAddons: [InstalledAddon] { enabled.filter { $0.supports(resource: "meta") } }

    func contains(manifestURL: URL) -> Bool {
        addons.contains { resolved($0).manifestURL == manifestURL || $0.manifestURL == manifestURL.redactedForAddonStorage }
    }

    /// Returns a copy with its Keychain-backed transport URL restored for network
    /// requests. Callers must not persist or display this resolved copy.
    func resolved(_ addon: InstalledAddon) -> InstalledAddon {
        guard let stored = KeychainStore.shared.get(addon.secureManifestAccount),
              let url = URL(string: stored) else { return addon }
        var copy = addon
        copy.manifestURL = url
        return copy
    }

    func resolvedAddon(id: UUID) -> InstalledAddon? {
        addons.first(where: { $0.id == id }).map(resolved)
    }

    // MARK: - Install / remove

    /// Installs an addon by manifest URL. Fetches and parses the manifest first.
    @discardableResult
    func install(manifestURL: URL) async throws -> InstalledAddon {
        if let existing = addons.first(where: { resolved($0).manifestURL == manifestURL }) {
            return existing
        }
        var addon = try await client.fetchManifest(at: manifestURL)
        if addon.manifestURLContainsSensitiveConfiguration {
            try KeychainStore.shared.set(manifestURL.absoluteString, for: addon.secureManifestAccount)
            addon.manifestURL = addon.redactedManifestURL
        }
        addons.append(addon)
        persist()
        return addon
    }

    func remove(_ addon: InstalledAddon) {
        guard let index = addons.firstIndex(where: { $0.id == addon.id }) else { return }
        let removed = addons.remove(at: index)
        lastRemoved = removed
        lastRemovedSecret = KeychainStore.shared.get(removed.secureManifestAccount)
        try? KeychainStore.shared.delete(removed.secureManifestAccount)
        persist()
    }

    func undoLastRemoval() {
        guard let addon = lastRemoved else { return }
        if let secret = lastRemovedSecret {
            try? KeychainStore.shared.set(secret, for: addon.secureManifestAccount)
        }
        addons.append(addon)
        lastRemoved = nil
        lastRemovedSecret = nil
        persist()
    }

    func setEnabled(_ addon: InstalledAddon, _ enabled: Bool) {
        guard let idx = addons.firstIndex(where: { $0.id == addon.id }) else { return }
        addons[idx].isEnabled = enabled
        persist()
    }

    func move(from source: IndexSet, to destination: Int) {
        addons.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    func move(id: UUID, before destinationID: UUID) {
        guard id != destinationID,
              let source = addons.firstIndex(where: { $0.id == id }),
              let destination = addons.firstIndex(where: { $0.id == destinationID }) else { return }
        let value = addons.remove(at: source)
        let adjusted = source < destination ? destination - 1 : destination
        addons.insert(value, at: adjusted)
        persist()
    }

    func move(id: UUID, offset: Int) {
        guard let source = addons.firstIndex(where: { $0.id == id }) else { return }
        let destination = min(max(source + offset, 0), addons.count - 1)
        guard destination != source else { return }
        addons.swapAt(source, destination)
        persist()
    }

    // MARK: - Categorization

    /// Sets (or clears) the user category for an addon.
    func setCategory(_ category: String?, for addon: InstalledAddon) {
        guard let idx = addons.firstIndex(where: { $0.id == addon.id }) else { return }
        let trimmed = category?.trimmingCharacters(in: .whitespacesAndNewlines)
        addons[idx].category = (trimmed?.isEmpty == false) ? trimmed : nil
        persist()
    }

    /// Replaces the tag list for an addon.
    func setTags(_ tags: [String], for addon: InstalledAddon) {
        guard let idx = addons.firstIndex(where: { $0.id == addon.id }) else { return }
        addons[idx].tags = tags
        persist()
    }

    /// All distinct categories currently in use, sorted.
    var categories: [String] {
        Set(addons.compactMap { $0.category }).sorted()
    }

    /// Enables or disables every addon in a category at once.
    func setEnabledForCategory(_ category: String, _ enabled: Bool) {
        for idx in addons.indices where addons[idx].category == category {
            addons[idx].isEnabled = enabled
        }
        persist()
    }

    // MARK: - Health

    /// A reachability result for an addon's manifest.
    enum Health: Equatable { case unknown, checking, reachable, broken(String) }

    /// Pings each addon's manifest and returns a map of addon id to health. Does not
    /// mutate stored state; the caller decides how to present it.
    func checkHealth() async -> [UUID: Health] {
        var result: [UUID: Health] = [:]
        var timings: [UUID: Int] = [:]
        var checked: [UUID: Date] = [:]
        await withTaskGroup(of: (UUID, Health, Int?).self) { group in
            for addon in addons {
                group.addTask {
                    let start = Date()
                    do {
                        let resolved = await self.resolved(addon)
                        _ = try await self.client.probe(addon: resolved)
                        let ms = Int(Date().timeIntervalSince(start) * 1000)
                        return (addon.id, .reachable, ms)
                    } catch {
                        return (addon.id, .broken(error.localizedDescription), nil)
                    }
                }
            }
            for await (id, health, ms) in group {
                result[id] = health
                checked[id] = Date()
                if let ms { timings[id] = ms }
            }
        }
        lastPingMS = timings
        lastHealthCheck = checked
        return result
    }

    /// Re-fetches every addon's manifest in the background (with retry/backoff),
    /// refreshes stored catalogs/descriptions, and flags addons whose advertised
    /// version is newer than the installed one. Returns how many updates were found.
    @discardableResult
    func refreshManifests() async -> Int {
        var found: [UUID: InstalledAddon] = [:]
        await withTaskGroup(of: (UUID, InstalledAddon?).self) { group in
            for addon in addons {
                group.addTask {
                    let resolved = await self.resolved(addon)
                    return (addon.id, try? await self.client.fetchManifestRetrying(at: resolved.manifestURL))
                }
            }
            for await (id, fresh) in group {
                guard let fresh, let idx = addons.firstIndex(where: { $0.id == id }) else { continue }
                let installed = addons[idx]
                if let newVersion = fresh.version, newVersion != installed.version {
                    found[id] = fresh
                }
            }
        }
        availableUpdates = found
        return found.count
    }

    func applyUpdate(for addon: InstalledAddon) {
        guard let fresh = availableUpdates[addon.id],
              let index = addons.firstIndex(where: { $0.id == addon.id }) else { return }
        addons[index].name = fresh.name
        addons[index].version = fresh.version
        addons[index].description = fresh.description
        addons[index].resources = fresh.resources
        addons[index].types = fresh.types
        addons[index].catalogs = fresh.catalogs
        availableUpdates.removeValue(forKey: addon.id)
        persist()
    }

    // MARK: - Import / Export

    /// A portable snapshot of the installed addons (manifest URLs plus user metadata),
    /// safe to share as a file. Contains no credentials.
    struct Export: Codable {
        struct Entry: Codable {
            var manifestURL: URL
            var name: String
            var isEnabled: Bool
            var category: String?
            var tags: [String]
            var requiresConfiguration: Bool?
        }
        var version: Int = 1
        var entries: [Entry]
    }

    /// Builds an export snapshot of the current addons.
    func makeExport() -> Export {
        Export(entries: addons.map {
            .init(manifestURL: $0.redactedManifestURL, name: $0.name,
                  isEnabled: $0.isEnabled, category: $0.category, tags: $0.tags,
                  requiresConfiguration: $0.requiresConfiguredURL)
        })
    }

    /// Encodes the current addons to pretty-printed JSON data for sharing.
    func exportData() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(makeExport())
    }

    /// Imports addons from an export snapshot. Installs any manifest not already
    /// present, then applies the saved enabled/category/tags. Returns how many were
    /// newly installed.
    @discardableResult
    func importData(_ data: Data) async -> Int {
        guard let snapshot = try? JSONDecoder().decode(Export.self, from: data) else { return 0 }
        var installed = 0
        for entry in snapshot.entries {
            if entry.requiresConfiguration == true { continue }
            if !contains(manifestURL: entry.manifestURL) {
                if (try? await install(manifestURL: entry.manifestURL)) != nil {
                    installed += 1
                }
            }
            if let idx = addons.firstIndex(where: { $0.manifestURL == entry.manifestURL }) {
                addons[idx].isEnabled = entry.isEnabled
                addons[idx].category = entry.category
                addons[idx].tags = entry.tags
            }
        }
        persist()
        return installed
    }

    // MARK: - First-run seeding

    /// Seeds Cinemeta (metadata) and any config-file addons if not present.
    /// Safe to call repeatedly; only installs what's missing.
    func seedDefaultsIfNeeded() async {
        if !contains(manifestURL: Self.cinemetaManifest) {
            _ = try? await install(manifestURL: Self.cinemetaManifest)
        }
        for url in AppConfig.shared.seedAddonURLs where !contains(manifestURL: url) {
            _ = try? await install(manifestURL: url)
        }
    }
}

private extension URL {
    var redactedForAddonStorage: URL {
        let shell = InstalledAddon(manifestURL: self, name: "")
        return shell.redactedManifestURL
    }
}
