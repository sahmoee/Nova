//
//  NovaPositionSync.swift
//  Nova
//
//  iCloud Key-Value Store sync for playback positions.
//  Keeps "continue watching" in sync across iPhone, iPad, and Apple TV.
//
//  Complements the existing CloudSync.swift (library metadata sync) by adding
//  lightweight per-item position sharing via NSUbiquitousKeyValueStore.
//
//  Wire-up:
//  1. Enable iCloud capability in Xcode → Signing & Capabilities → iCloud
//     and check "Key-value storage".
//  2. In AppEnvironment or NovaApp:
//       NovaPositionSync.shared.start()
//  3. In PlaybackProgressStore.save(position:duration:for:), add:
//       NovaPositionSync.shared.push(position: position, duration: duration, for: item)
//  4. On app launch / scene activation, call:
//       NovaPositionSync.shared.pull(into: library)
//

import Foundation

@MainActor
final class NovaPositionSync {
    static let shared = NovaPositionSync()

    private let store = NSUbiquitousKeyValueStore.default
    private let prefix = "nova.pos."
    private var started = false

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storeDidChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store
        )
        store.synchronize()
    }

    // MARK: - Push (local → iCloud)

    func push(position: TimeInterval, duration: TimeInterval?, for item: MediaItem) {
        guard position.isFinite, position > 5 else { return }
        let key = prefix + item.contentKey.replacingOccurrences(of: "|", with: "_")
        var payload: [String: Any] = [
            "pos": position,
            "ts": Date().timeIntervalSince1970
        ]
        if let d = duration, d.isFinite { payload["dur"] = d }
        store.set(payload, forKey: key)
        store.synchronize()
    }

    // MARK: - Pull (iCloud → library)

    /// Call this on launch or scene activation.
    /// Applies remote positions that are newer than what's locally stored.
    func pull(into library: LibraryStore) {
        let allKeys = store.dictionaryRepresentation.keys.filter { $0.hasPrefix(prefix) }
        for key in allKeys {
            guard let payload = store.dictionary(forKey: key),
                  let remotePos = payload["pos"] as? TimeInterval,
                  let remoteTs  = payload["ts"]  as? TimeInterval,
                  remotePos.isFinite
            else { continue }

            let contentKey = key.dropFirst(prefix.count)
                .replacingOccurrences(of: "_", with: "|")

            // Find the library item by content key.
            if var item = library.items.first(where: { $0.contentKey == String(contentKey) }) {
                // Only apply if remote is newer.
                let localTs = item.lastPlayedDate?.timeIntervalSince1970 ?? 0
                if remoteTs > localTs + 5 {
                    item.lastPlayedPosition = remotePos
                    item.lastPlayedDate = Date(timeIntervalSince1970: remoteTs)
                    if let dur = payload["dur"] as? TimeInterval, dur.isFinite {
                        item.duration = dur
                    }
                    library.update(item)
                }
            }
        }
    }

    // MARK: - External change handler

    @objc private func storeDidChange(_ notification: Notification) {
        // The library is not directly accessible here; post a notification
        // for AppEnvironment to handle the pull.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .novaPositionSyncDidReceiveUpdate, object: nil)
        }
    }
}

extension Notification.Name {
    /// Posted when iCloud pushed new playback positions to this device.
    /// In AppEnvironment: .onReceive(...) { NovaPositionSync.shared.pull(into: library) }
    static let novaPositionSyncDidReceiveUpdate = Notification.Name("nova.positionSync.didReceiveUpdate")
}
