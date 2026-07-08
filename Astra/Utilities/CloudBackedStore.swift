//
//  CloudBackedStore.swift
//  Astra
//
//  A generic Codable value persisted to UserDefaults + iCloud KVS with debounced
//  cloud pushes and an external-change publisher. Consolidates the load/persist/
//  externalChange sink pattern that several stores previously hand-rolled.
//
//  Local writes are immediate (no data-loss window on quit); the iCloud push and
//  flush are debounced so a burst of mutations produces one network write.
//

import Foundation
import Combine

@MainActor
final class CloudBackedStore<Value: Codable> {
    private let key: String
    private let debounce: Duration
    private var pushTask: Task<Void, Never>?

    init(key: String, debounce: Duration = .milliseconds(500)) {
        self.key = key
        self.debounce = debounce
    }

    /// Loads the stored value, preferring iCloud, then local defaults.
    func load() -> Value? {
        if let data = CloudSync.shared.data(forKey: key) ?? UserDefaults.standard.data(forKey: key),
           let decoded = try? Coders.decoder.decode(Value.self, from: data) {
            return decoded
        }
        return nil
    }

    /// Persists the value: local defaults immediately, iCloud after the debounce
    /// interval (restarted on every call, so bursts collapse into one push).
    func persist(_ value: Value) {
        guard let data = try? Coders.encoder.encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
        pushTask?.cancel()
        pushTask = Task { [debounce, key] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            CloudSync.shared.setData(data, forKey: key)
            CloudSync.shared.flush()
        }
    }

    /// Emits the freshly decoded value whenever another device changes this key.
    var externalChange: AnyPublisher<Value, Never> {
        CloudSync.shared.externalChange
            .receive(on: RunLoop.main)
            .compactMap { [key] changedKeys -> Value? in
                guard changedKeys.contains(key),
                      let data = CloudSync.shared.data(forKey: key),
                      let decoded = try? Coders.decoder.decode(Value.self, from: data)
                else { return nil }
                return decoded
            }
            .eraseToAnyPublisher()
    }
}
