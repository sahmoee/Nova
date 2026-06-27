//
//  BackupManager.swift
//  FrameTV
//
//  Creates a single "snapshot" that captures everything needed to reproduce the
//  user's setup on another device: preferences, SMB sources (with passwords),
//  installed addons, and all API keys / tokens from the Keychain. The snapshot is
//  stored in iCloud key-value storage so it follows the user's Apple ID, and can
//  be restored manually or offered automatically on a fresh install.
//
//  Secrets are included because the whole point is to move logins between the
//  user's own devices via their private iCloud. The snapshot lives only in the
//  user's iCloud KVS, never leaves Apple's sync, and is not written anywhere else.
//

import Foundation
#if os(iOS)
import UIKit
#endif

// MARK: - Snapshot model

struct BackupSnapshot: Codable {
    var version: Int = 1
    var createdAt: Date = Date()
    var deviceName: String = ""

    /// Non-secret preference key/values mirrored from iCloud KVS / UserDefaults.
    var settings: [String: BackupValue] = [:]
    /// Raw JSON for SMB shares and addons (as stored locally).
    var smbSharesJSON: Data?
    var addonsJSON: Data?
    /// Keychain secrets: account -> value. Includes API keys, tokens, and the
    /// per-share SMB passwords (accounts of the form "smb.<uuid>").
    var secrets: [String: String] = [:]
}

/// A small sum type so we can round-trip the handful of value kinds in settings.
enum BackupValue: Codable {
    case bool(Bool)
    case string(String)
}

// MARK: - Manager

@MainActor
final class BackupManager: ObservableObject {

    static let shared = BackupManager()

    /// iCloud KVS key holding the latest snapshot.
    private static let cloudKey = "backup.snapshot.v1"

    @Published private(set) var lastBackupDate: Date?

    private let keychain = KeychainStore.shared

    init() {
        if let snap = loadSnapshotFromCloud() {
            lastBackupDate = snap.createdAt
        }
    }

    // MARK: - Settings keys to capture

    /// The non-secret preference keys backed up (kept in sync with SettingsStore).
    private let settingBoolKeys = [
        "settings.resumePlayback", "settings.autoPlayNext", "settings.skipIntro",
        "settings.autoSkipIntro", "settings.skipOutro", "settings.autoSelectStream",
        "settings.requireCachedStreams", "settings.subtitlesEnabled",
        "settings.traktScrobbling", "settings.requireLegalConfirmation"
    ]
    private let settingStringKeys = [
        "settings.defaultQuality", "settings.preferredStreamQuality", "settings.subtitleLanguage"
    ]

    /// All Keychain accounts to capture: the credential keys, the Real-Debrid
    /// token, plus any per-share SMB password accounts derived from the shares.
    private func secretAccounts(smbShareIDs: [UUID]) -> [String] {
        var accounts = [
            "tmdb.apiKey", "trakt.clientId", "trakt.clientSecret",
            "trakt.accessToken", "trakt.refreshToken", "opensubtitles.apiKey",
            KeychainStore.realDebridTokenAccount
        ]
        accounts.append(contentsOf: smbShareIDs.map { "smb.\($0.uuidString)" })
        return accounts
    }

    // MARK: - Create

    /// Builds a snapshot from the current device state and writes it to iCloud.
    func createBackup() {
        var snap = BackupSnapshot()
        snap.deviceName = deviceName()

        // Settings.
        let defaults = UserDefaults.standard
        for k in settingBoolKeys where defaults.object(forKey: k) != nil {
            snap.settings[k] = .bool(defaults.bool(forKey: k))
        }
        for k in settingStringKeys {
            if let v = defaults.string(forKey: k) { snap.settings[k] = .string(v) }
        }

        // Sources + addons: copy the raw JSON files if present.
        snap.smbSharesJSON = readSupportFile("smb_shares.json")
        snap.addonsJSON = readSupportFile("addons.json")

        // Secrets from Keychain.
        let shareIDs = smbShareIDs(from: snap.smbSharesJSON)
        for account in secretAccounts(smbShareIDs: shareIDs) {
            if let value = keychain.get(account) {
                snap.secrets[account] = value
            }
        }

        // Persist to iCloud.
        if let data = try? JSONEncoder().encode(snap) {
            CloudSync.shared.setData(data, forKey: Self.cloudKey)
            CloudSync.shared.flush()
            lastBackupDate = snap.createdAt
            FrameLog.sync.info("Created backup snapshot (\(snap.secrets.count) secrets)")
        }
    }

    // MARK: - Restore

    /// Whether a snapshot exists in iCloud that could be restored.
    func hasCloudSnapshot() -> Bool { loadSnapshotFromCloud() != nil }

    /// Returns metadata about the available snapshot for confirmation UI.
    func availableSnapshotInfo() -> (date: Date, device: String)? {
        guard let snap = loadSnapshotFromCloud() else { return nil }
        return (snap.createdAt, snap.deviceName)
    }

    /// Restores everything from the iCloud snapshot onto this device. Returns true
    /// on success. Existing local data is overwritten by the snapshot.
    @discardableResult
    func restoreFromCloud() -> Bool {
        guard let snap = loadSnapshotFromCloud() else { return false }

        // Settings.
        let defaults = UserDefaults.standard
        for (k, v) in snap.settings {
            switch v {
            case .bool(let b):   defaults.set(b, forKey: k); CloudSync.shared.setBool(b, forKey: k)
            case .string(let s): defaults.set(s, forKey: k); CloudSync.shared.setString(s, forKey: k)
            }
        }

        // Sources + addons JSON written back to disk + mirrored to iCloud.
        if let data = snap.smbSharesJSON {
            writeSupportFile("smb_shares.json", data)
            CloudSync.shared.setData(data, forKey: "cloud.smbShares")
        }
        if let data = snap.addonsJSON {
            writeSupportFile("addons.json", data)
            CloudSync.shared.setData(data, forKey: "cloud.addons")
        }

        // Secrets back into the Keychain.
        for (account, value) in snap.secrets {
            try? keychain.set(value, for: account)
        }

        CloudSync.shared.flush()
        FrameLog.sync.info("Restored backup snapshot from \(snap.deviceName, privacy: .public)")
        return true
    }

    // MARK: - Helpers

    private func loadSnapshotFromCloud() -> BackupSnapshot? {
        guard let data = CloudSync.shared.data(forKey: Self.cloudKey) else { return nil }
        return try? JSONDecoder().decode(BackupSnapshot.self, from: data)
    }

    private func smbShareIDs(from json: Data?) -> [UUID] {
        guard let json,
              let shares = try? JSONDecoder().decode([SMBShare].self, from: json) else { return [] }
        return shares.map { $0.id }
    }

    private func supportURL(_ name: String) -> URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }

    private func readSupportFile(_ name: String) -> Data? {
        try? Data(contentsOf: supportURL(name))
    }

    private func writeSupportFile(_ name: String, _ data: Data) {
        try? data.write(to: supportURL(name), options: [.atomic])
    }

    private func deviceName() -> String {
        #if os(iOS)
        return UIDevice.current.name
        #else
        return "Apple TV"
        #endif
    }
}
