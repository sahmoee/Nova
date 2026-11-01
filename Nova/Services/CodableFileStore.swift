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
    private let maximumBytes = 16 * 1_024 * 1_024
    private let validate: (Value) -> Bool
    private(set) var lastError: String?
    private(set) var needsRecovery = false
    private var cancellable: AnyCancellable?

    /// Called when an external (cloud) change replaces the value, so the owner can
    /// update its published state.
    var onExternalChange: ((Value) -> Void)?

    init(filename: String, cloudKey: String? = nil, prettyPrinted: Bool = true,
         directory: URL? = nil, validate: @escaping (Value) -> Bool = { _ in true }) {
        let support = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.validate = validate
        self.fileURL = support.appendingPathComponent(filename)
        self.cloudKey = cloudKey
        if prettyPrinted { encoder.outputFormatting = [.prettyPrinted] }

        if let cloudKey {
            cancellable = CloudSync.shared.externalChange
                .receive(on: RunLoop.main)
                .sink { [weak self] keys in
                    guard let self, keys.contains(cloudKey) else { return }
                    if !self.needsRecovery, let merged = self.loadFromCloud(), self.writeLocal(merged) {
                        self.onExternalChange?(merged)
                    }
                }
        }
    }

    // MARK: - Load

    /// Loads the value, preferring a newer iCloud copy if present.
    func load() -> Value? {
        let local = loadLocal()
        if !needsRecovery, let cloud = loadFromCloud(), cloud != local, writeLocal(cloud) {
            return cloud
        }
        return local
    }

    private func loadLocal() -> Value? {
        guard FileManager.default.fileExists(atPath: fileURL.path)
            || (try? fileURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true else { return nil }
        do {
            let data = try LibraryFilePolicy.read(fileURL, maximumBytes: maximumBytes)
            let value = try decoder.decode(Value.self, from: data)
            guard validate(value) else { throw LibraryFilePolicy.Failure.invalidFile }
            needsRecovery = false; lastError = nil
            return value
        } catch {
            needsRecovery = true
            lastError = "Saved download records could not be read. Their original file has been preserved; restore a valid backup before downloading."
            return nil
        }
    }

    private func loadFromCloud() -> Value? {
        guard let cloudKey, let data = CloudSync.shared.data(forKey: cloudKey), data.count <= maximumBytes,
              let value = try? decoder.decode(Value.self, from: data), validate(value) else { return nil }
        return value
    }

    // MARK: - Save

    /// Persists locally and mirrors to iCloud (if a cloud key was provided).
    @discardableResult
    func save(_ value: Value) -> Bool {
        guard writeLocal(value) else { return false }
        if let cloudKey, let data = try? encoder.encode(value) {
            CloudSync.shared.setData(data, forKey: cloudKey)
        }
        return true
    }

    /// Explicit recovery only: retain the unreadable original beside the fresh
    /// journal. Existing media files are not moved or deleted.
    func resetRetainingOriginal(_ value: Value) -> Bool {
        let backup = fileURL.appendingPathExtension("recovery-\(UUID().uuidString)")
        let hadOriginal = FileManager.default.fileExists(atPath: fileURL.path)
            || (try? fileURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
        do {
            if hadOriginal { try FileManager.default.moveItem(at: fileURL, to: backup) }
            needsRecovery = false
            guard save(value) else {
                if hadOriginal { try FileManager.default.moveItem(at: backup, to: fileURL) }
                needsRecovery = true
                return false
            }
            return true
        } catch {
            needsRecovery = true
            lastError = "Download recovery could not preserve the original records. No reset was completed."
            return false
        }
    }

    private func writeLocal(_ value: Value) -> Bool {
        guard !needsRecovery else { return false }
        do {
            guard validate(value) else { throw LibraryFilePolicy.Failure.invalidFile }
            let data = try encoder.encode(value)
            try LibraryFilePolicy.write(data, to: fileURL, maximumBytes: maximumBytes)
            lastError = nil
            return true
        } catch {
            lastError = "Download changes could not be saved. Check available storage and retry before quitting."
            return false
        }
    }
}
