//
//  CloudSync.swift
//  Nova
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
import CryptoKit

@MainActor
final class CloudSync: ObservableObject {

    static let shared = CloudSync()

    private let store = NSUbiquitousKeyValueStore.default
    @Published private(set) var lastSyncRequest: Date?
    @Published private(set) var lastExternalChange: Date?
    @Published private(set) var syncIssue: String?
    private var suppressWrites = false

    var accountAvailable: Bool { FileManager.default.ubiquityIdentityToken != nil }
    var storedKeys: [String] { Array(store.dictionaryRepresentation.keys) }

    func isPaused(_ domain: SettingsDataDomain) -> Bool {
        UserDefaults.standard.bool(forKey: domain.pausedKey)
    }

    func deletionDate(_ domain: SettingsDataDomain) -> Double {
        max(UserDefaults.standard.double(forKey: domain.deletionKey), store.double(forKey: domain.deletionKey))
    }
    func sharedDeletionDate(_ domain: SettingsDataDomain) -> Double { store.double(forKey: domain.deletionKey) }
    func rawMirrorData(forKey key: String) -> Data? { store.data(forKey: key) }

    /// Used only to redact a selected category from a shared composite mirror.
    func replaceMirrorAfterDeletion(_ data: Data, forKey key: String) {
        store.set(data, forKey: key)
        recordWrite(key)
        scheduleFlush()
    }

    func acknowledgedDeletion(_ domain: SettingsDataDomain) -> Double {
        let consumers: [String]
        switch domain {
        case .history: consumers = [".library", ".streams"]
        case .library: consumers = [".library"]
        case .addons: consumers = [".addons"]
        case .preferences: consumers = [""]
        }
        return consumers.map { UserDefaults.standard.double(forKey: domain.appliedKey + $0) }.min() ?? 0
    }

    func consumeDeletion(_ domain: SettingsDataDomain, consumer: String = "") -> Bool {
        let date = deletionDate(domain)
        let appliedKey = domain.appliedKey + consumer
        guard date > UserDefaults.standard.double(forKey: appliedKey) else { return false }
        UserDefaults.standard.set(date, forKey: domain.deletionKey)
        UserDefaults.standard.set(date, forKey: appliedKey)
        return true
    }

    func retryDeletion(_ domain: SettingsDataDomain, consumer: String) {
        UserDefaults.standard.removeObject(forKey: domain.appliedKey + consumer)
    }

    func beginDeletion(_ domain: SettingsDataDomain, includingCloud: Bool) {
        let date = Date().timeIntervalSince1970
        UserDefaults.standard.set(date, forKey: domain.deletionKey)
        UserDefaults.standard.set(true, forKey: domain.pausedKey)
        if includingCloud {
            store.set(date, forKey: domain.deletionKey)
            for key in storedKeys where SettingsDataPolicy.domain(for: key) == domain {
                store.removeObject(forKey: key)
            }
            flush()
        }
        externalChange.send([domain.deletionKey])
    }

    func resumeSync(_ domain: SettingsDataDomain, pulling: Bool = false) {
        UserDefaults.standard.set(false, forKey: domain.pausedKey)
        if pulling {
            // A deliberate Pull can restore a device-only reset from its untouched
            // cloud copy. Shared deletion markers continue to apply.
            UserDefaults.standard.set(sharedDeletionDate(domain), forKey: domain.deletionKey)
        }
    }

    func withoutCloudWrites(_ work: () -> Void) {
        let old = suppressWrites
        suppressWrites = true
        defer { suppressWrites = old }
        work()
    }

    private func canRead(_ key: String) -> Bool {
        guard let domain = SettingsDataPolicy.domain(for: key) else { return true }
        guard SettingsDataPolicy.accepts(revision: store.double(forKey: "nova.data.modified." + key),
                                         deletedAt: deletionDate(domain), paused: isPaused(domain)) else { return false }
        // A legacy writer may replace a value without replacing our stamp. Bind
        // the acknowledgement to its actual bytes before accepting it after a reset.
        return deletionDate(domain) <= 0 || fingerprint(key) == store.string(forKey: "nova.data.fingerprint." + key)
    }

    private func prepareWrite(_ key: String) -> Bool {
        guard !suppressWrites else { return false }
        if let domain = SettingsDataPolicy.domain(for: key) {
            guard !isPaused(domain) else { return false }
            guard acknowledgedDeletion(domain) >= sharedDeletionDate(domain) else { return false }
            if domain == .library {
                guard UserDefaults.standard.double(forKey: SettingsDataDomain.history.appliedKey + ".library")
                    >= sharedDeletionDate(.history) else { return false }
            }
        }
        return true
    }

    private func fingerprint(_ key: String) -> String? {
        guard let value = store.object(forKey: key),
              let data = try? PropertyListSerialization.data(fromPropertyList: ["value": value], format: .binary, options: 0)
        else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func recordWrite(_ key: String) {
        guard SettingsDataPolicy.domain(for: key) != nil else { return }
        store.set(Date().timeIntervalSince1970, forKey: "nova.data.modified." + key)
        if let digest = fingerprint(key) { store.set(digest, forKey: "nova.data.fingerprint." + key) }
        else { store.removeObject(forKey: "nova.data.fingerprint." + key) }
    }

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

    // IMPORTANT: this handler MUST stay `nonisolated`.
    //
    // `CloudSync` is `@MainActor`, so *without* `nonisolated` this @objc method is
    // implicitly main-actor-isolated. iCloud (the SyncedDefaults daemon) posts
    // `didChangeExternallyNotification` on a background queue, and NotificationCenter
    // invokes this selector synchronously on that background queue. On iOS 18+ /
    // Swift 6 runtimes the compiler inserts an executor precondition at the start of
    // an isolated @objc method; when the selector fires off-main that precondition
    // calls `dispatch_assert_queue(main)`, which fails and hard-crashes the app with
    // EXC_BREAKPOINT (SIGTRAP) *before the body runs* — so the `Task { @MainActor }`
    // hop below is never reached and cannot help.
    //
    // Marking the method `nonisolated` lets the notification be delivered on any
    // thread without the precondition. We read the Sendable `keys` array here (off
    // the main actor is fine — we only touch the immutable `note`) and then hop onto
    // the main actor to publish through `externalChange`.
    @objc private nonisolated func handleExternalChange(_ note: Notification) {
        let keys = (note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]) ?? []
        let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
        Task { @MainActor in
            self.lastExternalChange = Date()
            self.syncIssue = reason == NSUbiquitousKeyValueStoreQuotaViolationChange
                ? "iCloud storage quota reached. Local data is preserved." : nil
            self.externalChange.send(Set(keys))
        }
    }

    // MARK: - Primitive accessors

    func bool(forKey key: String) -> Bool? {
        guard canRead(key), store.object(forKey: key) != nil else { return nil }
        return store.bool(forKey: key)
    }
    func setBool(_ value: Bool, forKey key: String) {
        guard prepareWrite(key) else { return }
        store.set(value, forKey: key); recordWrite(key); scheduleFlush()
    }

    func string(forKey key: String) -> String? { canRead(key) ? store.string(forKey: key) : nil }
    func setString(_ value: String?, forKey key: String) {
        guard prepareWrite(key) else { return }
        if let value { store.set(value, forKey: key) } else { store.removeObject(forKey: key) }
        recordWrite(key)
        scheduleFlush()
    }

    func data(forKey key: String) -> Data? { canRead(key) ? store.data(forKey: key) : nil }
    func setData(_ value: Data?, forKey key: String) {
        guard prepareWrite(key) else { return }
        if let value { store.set(value, forKey: key) } else { store.removeObject(forKey: key) }
        recordWrite(key)
        scheduleFlush()
    }

    func double(forKey key: String) -> Double? {
        guard canRead(key), store.object(forKey: key) != nil else { return nil }
        return store.double(forKey: key)
    }
    func setDouble(_ value: Double, forKey key: String) {
        guard prepareWrite(key) else { return }
        store.set(value, forKey: key); recordWrite(key); scheduleFlush()
    }

    func object(forKey key: String) -> Any? { canRead(key) ? store.object(forKey: key) : nil }

    /// Pushes any pending changes to iCloud immediately.
    /// Pulls the newest iCloud values down before reading a snapshot.
    func pull() {
        requestSync()
    }

    func flush() {
        flushWorkItem?.cancel()
        flushWorkItem = nil
        requestSync()
    }

    private func requestSync() {
        lastSyncRequest = Date()
        if !accountAvailable { syncIssue = "iCloud account unavailable; changes remain on this device." }
        else if !store.synchronize() { syncIssue = "iCloud sync request could not start. Try again later." }
        else { syncIssue = nil }
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
