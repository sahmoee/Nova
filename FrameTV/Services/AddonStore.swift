//
//  AddonStore.swift
//  FrameTV
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
