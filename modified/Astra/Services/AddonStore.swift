//
//  AddonStore.swift
//  Astra
//
//  Persists the user's installed addons to a local JSON file and exposes them to
//  the rest of the app. Seeds Stremio's public Cinemeta metadata addon on first
//  run so series/episode metadata works out of the box, plus any addon URLs from
//  the optional config file.
//

import Foundation
import Combine

@MainActor
final class AddonStore: ObservableObject {

    @Published private(set) var addons: [InstalledAddon] = []
    /// Last health-check response time per addon, in milliseconds.
    @Published private(set) var lastPingMS: [UUID: Int] = [:]
    /// Addons whose manifest advertises a newer version than the installed copy.
    @Published private(set) var updateAvailable: Set<UUID> = []

    private let fileURL: URL
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
        encoder.outputFormatting = [.prettyPrinted]
        load()
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
            forName: .astraBackupRestored, object: nil, queue: .main
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
        guard let data = try? encoder.encode(addons) else { return }
        try? data.write(to: fileURL, options: [.atomic])
        // Mirror to iCloud for cross-device sync.
        CloudSync.shared.setData(data, forKey: Self.cloudKey)
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
            if let encoded = try? encoder.encode(addons) {
                try? encoded.write(to: fileURL, options: [.atomic])
            }
        }
    }

    // MARK: - Queries

    /// Enabled addons, unless Safe Mode is on (in which case none are active, so a
    /// misbehaving addon can't stall catalogs, streams, or subtitles).
    var enabled: [InstalledAddon] { SafeMode.isOn ? [] : addons.filter { $0.isEnabled } }
    var streamAddons: [InstalledAddon] { enabled.filter { $0.supports(resource: "stream") } }
    var subtitleAddons: [InstalledAddon] { enabled.filter { $0.supports(resource: "subtitles") } }
    var metaAddons: [InstalledAddon] { enabled.filter { $0.supports(resource: "meta") } }

    func contains(manifestURL: URL) -> Bool {
        addons.contains { $0.manifestURL == manifestURL }
    }

    // MARK: - Install / remove

    /// Installs an addon by manifest URL. Fetches and parses the manifest first.
    @discardableResult
    func install(manifestURL: URL) async throws -> InstalledAddon {
        if let existing = addons.first(where: { $0.manifestURL == manifestURL }) {
            return existing
        }
        let addon = try await client.fetchManifest(at: manifestURL)
        addons.append(addon)
        persist()
        return addon
    }

    func remove(_ addon: InstalledAddon) {
        addons.removeAll { $0.id == addon.id }
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
        await withTaskGroup(of: (UUID, Health, Int?).self) { group in
            for addon in addons {
                group.addTask {
                    let start = Date()
                    do {
                        _ = try await self.client.fetchManifest(at: addon.manifestURL)
                        let ms = Int(Date().timeIntervalSince(start) * 1000)
                        return (addon.id, .reachable, ms)
                    } catch {
                        return (addon.id, .broken(error.localizedDescription), nil)
                    }
                }
            }
            for await (id, health, ms) in group {
                result[id] = health
                if let ms { timings[id] = ms }
            }
        }
        lastPingMS = timings
        return result
    }

    /// Re-fetches every addon's manifest in the background (with retry/backoff),
    /// refreshes stored catalogs/descriptions, and flags addons whose advertised
    /// version is newer than the installed one. Returns how many updates were found.
    @discardableResult
    func refreshManifests() async -> Int {
        var found: Set<UUID> = []
        await withTaskGroup(of: (UUID, InstalledAddon?).self) { group in
            for addon in addons {
                group.addTask {
                    (addon.id, try? await self.client.fetchManifestRetrying(at: addon.manifestURL))
                }
            }
            for await (id, fresh) in group {
                guard let fresh, let idx = addons.firstIndex(where: { $0.id == id }) else { continue }
                let installed = addons[idx]
                if let newVersion = fresh.version, newVersion != installed.version {
                    found.insert(id)
                }
                // Refresh the metadata that can drift server-side, keeping the
                // user's id, enabled state, category, and tags intact.
                addons[idx].name = fresh.name
                addons[idx].version = fresh.version
                addons[idx].catalogs = fresh.catalogs
            }
        }
        updateAvailable = found
        return found.count
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
        }
        var version: Int = 1
        var entries: [Entry]
    }

    /// Builds an export snapshot of the current addons.
    func makeExport() -> Export {
        Export(entries: addons.map {
            .init(manifestURL: $0.manifestURL, name: $0.name,
                  isEnabled: $0.isEnabled, category: $0.category, tags: $0.tags)
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
