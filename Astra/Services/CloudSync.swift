//
//  CloudSync.swift
//  Astra
//
//  A thin wrapper over NSUbiquitousKeyValueStore (iCloud key-value storage) used
//  to sync small pieces of state across the user's devices: preferences, sources
//  (SMB shares), and installed addons. iCloud KVS has a ~1MB total budget which
//  is ample for these.
//
//  Usage pattern: write to both the local store (UserDefaults / file) and here,
//  and on launch / on external change, merge iCloud values back in.
//

import Foundation
import Combine

@MainActor
final class CloudSync: ObservableObject {

    static let shared = CloudSync()

    private let store = NSUbiquitousKeyValueStore.default

    /// Emits when iCloud reports that values changed on another device.
    let externalChange = PassthroughSubject<Set<String>, Never>()

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleExternalChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store
        )
        store.synchronize()
    }

    // MARK: - External change handling

    @objc private func handleExternalChange(_ note: Notification) {
        let keys = (note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]) ?? []
        Task { @MainActor in
            self.externalChange.send(Set(keys))
        }
    }

    // MARK: - Primitive accessors

    func bool(forKey key: String) -> Bool? {
        guard store.object(forKey: key) != nil else { return nil }
        return store.bool(forKey: key)
    }
    func setBool(_ value: Bool, forKey key: String) {
        store.set(value, forKey: key); scheduleFlush()
    }

    func string(forKey key: String) -> String? { store.string(forKey: key) }
    func setString(_ value: String?, forKey key: String) {
        if let value { store.set(value, forKey: key) } else { store.removeObject(forKey: key) }
        scheduleFlush()
    }

    func data(forKey key: String) -> Data? { store.data(forKey: key) }
    func setData(_ value: Data?, forKey key: String) {
        if let value { store.set(value, forKey: key) } else { store.removeObject(forKey: key) }
        scheduleFlush()
    }

    func double(forKey key: String) -> Double? {
        guard store.object(forKey: key) != nil else { return nil }
        return store.double(forKey: key)
    }
    func setDouble(_ value: Double, forKey key: String) {
        store.set(value, forKey: key); scheduleFlush()
    }

    func object(forKey key: String) -> Any? { store.object(forKey: key) }

    /// Pushes any pending changes to iCloud immediately.
    func flush() {
        flushWorkItem?.cancel()
        flushWorkItem = nil
        store.synchronize()
    }

    // MARK: - Coalesced flush
    //
    // iCloud KVS throttles synchronize() calls, so instead of flushing on every
    // single set, we debounce: batch rapid writes (e.g. toggling several settings)
    // into one synchronize a short moment later.

    private var flushWorkItem: DispatchWorkItem?

    private func scheduleFlush() {
        flushWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.store.synchronize()
            self?.flushWorkItem = nil
        }
        flushWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }
}
