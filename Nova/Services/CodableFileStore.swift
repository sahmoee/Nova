//
//  CodableFileStore.swift
//  Nova
//
//  A reusable persistence helper that captures the load / save / iCloud-mirror /
//  external-merge pattern currently duplicated across LibraryStore, AddonStore,
//  and SMBSharesModel. New stores can build on this instead of re-implementing it.
//
//  It persists a Codable value to a JSON file in Application Support and, when a
//  cloud key is provided, mirrors it to iCloud key-value storage and merges
//  external changes.
//

import Foundation
import Combine

@MainActor
final class CodableFileStore<Value: Codable & Equatable> {

    private let fileURL: URL
    private let cloudKey: String?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var cancellable: AnyCancellable?

    /// Called when an external (cloud) change replaces the value, so the owner can
    /// update its published state.
    var onExternalChange: ((Value) -> Void)?

    init(filename: String, cloudKey: String? = nil, prettyPrinted: Bool = true) {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        self.fileURL = support.appendingPathComponent(filename)
        self.cloudKey = cloudKey
        if prettyPrinted { encoder.outputFormatting = [.prettyPrinted] }

        if let cloudKey {
            cancellable = CloudSync.shared.externalChange
                .receive(on: RunLoop.main)
                .sink { [weak self] keys in
                    guard let self, keys.contains(cloudKey) else { return }
                    if let merged = self.loadFromCloud() {
                        self.writeLocal(merged)
                        self.onExternalChange?(merged)
                    }
                }
        }
    }

    // MARK: - Load

    /// Loads the value, preferring a newer iCloud copy if present.
    func load() -> Value? {
        let local = loadLocal()
        if let cloud = loadFromCloud(), cloud != local {
            writeLocal(cloud)
            return cloud
        }
        return local
    }

    private func loadLocal() -> Value? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(Value.self, from: data)
    }

    private func loadFromCloud() -> Value? {
        guard let cloudKey, let data = CloudSync.shared.data(forKey: cloudKey) else { return nil }
        return try? decoder.decode(Value.self, from: data)
    }

    // MARK: - Save

    /// Persists locally and mirrors to iCloud (if a cloud key was provided).
    func save(_ value: Value) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: fileURL, options: [.atomic])
        if let cloudKey {
            CloudSync.shared.setData(data, forKey: cloudKey)
        }
    }

    private func writeLocal(_ value: Value) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
