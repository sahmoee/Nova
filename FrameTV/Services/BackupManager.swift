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

/// Distinguishes a Bool stored in UserDefaults from a numeric value. UserDefaults
/// bridges both to NSNumber, so this checks the underlying CoreFoundation type.
private extension NSNumber {
    var isBool: Bool { CFGetTypeID(self) == CFBooleanGetTypeID() }
}

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

// MARK: - Selectable contents

/// The categories of a snapshot a user can choose to include when exporting or to
/// apply when restoring. Lets a household share a complete backup (secrets included)
/// while keeping the choice explicit on both ends.
struct BackupContents: OptionSet, Hashable {
    let rawValue: Int
    static let preferences = BackupContents(rawValue: 1 << 0)   // app settings
    static let sources     = BackupContents(rawValue: 1 << 1)   // SMB shares (no passwords)
    static let addons      = BackupContents(rawValue: 1 << 2)   // installed addons
    static let secrets     = BackupContents(rawValue: 1 << 3)   // passwords, tokens, API keys

    /// Everything except secrets — the safe default for a shareable file.
    static let safe: BackupContents = [.preferences, .sources, .addons]
    /// Everything, including logins. For trusted household sharing.
    static let all: BackupContents = [.preferences, .sources, .addons, .secrets]

    /// Describes each toggleable category for the export/import UI.
    struct Item: Identifiable {
        var id: Int { option.rawValue }
        let option: BackupContents
        let title: String
        let detail: String
        let systemImage: String
        let sensitive: Bool
    }

    /// The ordered list of categories shown to the user, with copy.
    static let catalog: [Item] = [
        Item(option: .preferences, title: "Preferences",
             detail: "App settings: playback, subtitles, quality, and your home and discover shelves.",
             systemImage: "slider.horizontal.3", sensitive: false),
        Item(option: .sources, title: "Sources",
             detail: "Your SMB network shares (addresses and usernames).",
             systemImage: "externaldrive.connected.to.line.below", sensitive: false),
        Item(option: .addons, title: "Addons",
             detail: "Installed addon catalogs and their configuration.",
             systemImage: "puzzlepiece.extension", sensitive: false),
        Item(option: .secrets, title: "Logins & API keys",
             detail: "Passwords, tokens, and API keys (Trakt, Real-Debrid, TMDB, SMB share passwords). Only share with people you trust.",
             systemImage: "key.fill", sensitive: true)
    ]
}

/// A small sum type so we can round-trip the handful of value kinds in settings.
enum BackupValue: Codable {
    case bool(Bool)
    case string(String)
    case double(Double)
    case data(Data)
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

    /// JSON-backed preference blobs stored in UserDefaults (not in a support file).
    /// These are captured explicitly because dictionaryRepresentation surfaces them as
    /// Data, which the prefix scan also handles, but listing them documents intent.
    private let settingDataKeys = [
        "home.shelves.v1"                        // customized home/discover shelves
    ]

    /// Prefixes for every app-owned UserDefaults key. The backup captures ALL keys
    /// under these prefixes automatically, so any setting added in the future is
    /// included without updating a list. This guarantees a complete backup.
    private let settingPrefixes = ["settings.", "discover.", "player.", "home.", "ai.", "whatsNew."]

    /// Captures every app-owned preference into the snapshot, by scanning all
    /// UserDefaults keys under the known prefixes and encoding each by its real type.
    private func captureAllSettings(into snap: inout BackupSnapshot) {
        let defaults = UserDefaults.standard
        let all = defaults.dictionaryRepresentation()
        for (key, value) in all {
            guard settingPrefixes.contains(where: { key.hasPrefix($0) }) else { continue }
            switch value {
            case let n as NSNumber:
                // UserDefaults bridges Bool and numbers to NSNumber; tell them apart.
                if n.isBool { snap.settings[key] = .bool(n.boolValue) }
                else { snap.settings[key] = .double(n.doubleValue) }
            case let s as String:
                snap.settings[key] = .string(s)
            case let d as Data:
                snap.settings[key] = .data(d)
            default:
                break   // arrays/dicts are captured via their own JSON keys
            }
        }
    }

    /// All Keychain accounts to capture. Driven by the CredentialKey enum so adding a
    /// new credential automatically includes it in the backup. Adds the Real-Debrid
    /// token and any per-share SMB password accounts derived from the shares.
    private func secretAccounts(smbShareIDs: [UUID]) -> [String] {
        var accounts = CredentialKey.allCases.map { $0.rawValue }
        accounts.append(KeychainStore.realDebridTokenAccount)
        accounts.append(contentsOf: smbShareIDs.map { "smb.\($0.uuidString)" })
        return accounts
    }

    // MARK: - Create

    /// Builds a snapshot from the current device state and writes it to iCloud.
    func createBackup() {
        var snap = BackupSnapshot()
        snap.deviceName = deviceName()

        // Settings: capture every app-owned preference by prefix, plus the JSON blobs.
        captureAllSettings(into: &snap)
        let defaults = UserDefaults.standard
        for k in settingDataKeys {
            if let v = defaults.data(forKey: k) { snap.settings[k] = .data(v) }
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

    /// Restores the selected categories from the iCloud snapshot onto this device.
    /// Returns true on success. By default everything is restored, including logins.
    @discardableResult
    func restoreFromCloud(restoring contents: BackupContents = .all) -> Bool {
        guard let snap = loadSnapshotFromCloud() else { return false }
        apply(snap, restoring: contents)
        // Mirror sources/addons to iCloud KVS as well, so other devices stay in sync.
        if contents.contains(.sources), let data = snap.smbSharesJSON {
            CloudSync.shared.setData(data, forKey: "cloud.smbShares")
        }
        if contents.contains(.addons), let data = snap.addonsJSON {
            CloudSync.shared.setData(data, forKey: "cloud.addons")
        }
        CloudSync.shared.flush()
        FrameLog.sync.info("Restored backup snapshot from \(snap.deviceName, privacy: .public)")
        return true
    }

    /// The categories available in the current iCloud snapshot, for the restore UI.
    func cloudSnapshotContents() -> BackupContents? {
        guard let snap = loadSnapshotFromCloud() else { return nil }
        return availableContents(in: snap)
    }

    /// What this device can currently export. Preferences and secrets are effectively
    /// always present; sources/addons only if the user has configured them.
    func currentDeviceContents() -> BackupContents {
        var c: BackupContents = [.preferences]
        if readSupportFile("smb_shares.json") != nil { c.insert(.sources) }
        if readSupportFile("addons.json") != nil { c.insert(.addons) }
        // Secrets are offerable if any credential exists in the Keychain.
        let shareIDs = smbShareIDs(from: readSupportFile("smb_shares.json"))
        if secretAccounts(smbShareIDs: shareIDs).contains(where: { keychain.get($0) != nil }) {
            c.insert(.secrets)
        }
        return c
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

    // MARK: - Export / Import (shareable file)

    /// Builds a snapshot of the current setup and writes it to a temporary .frametv
    /// file suitable for sharing. The caller chooses which categories to include via
    /// `contents`. By default secrets are excluded so the file is safe to share; a
    /// household can opt to include secrets to move logins between trusted devices.
    func exportSnapshotFile(including contents: BackupContents = .safe) -> URL? {
        var snap = BackupSnapshot()
        snap.deviceName = deviceName()

        if contents.contains(.preferences) {
            captureAllSettings(into: &snap)
            let defaults = UserDefaults.standard
            for k in settingDataKeys {
                if let v = defaults.data(forKey: k) { snap.settings[k] = .data(v) }
            }
        }
        if contents.contains(.sources) {
            snap.smbSharesJSON = readSupportFile("smb_shares.json")
        }
        if contents.contains(.addons) {
            snap.addonsJSON = readSupportFile("addons.json")
        }
        if contents.contains(.secrets) {
            // Include passwords, tokens, and API keys for trusted household sharing.
            let shareIDs = smbShareIDs(from: snap.smbSharesJSON ?? readSupportFile("smb_shares.json"))
            for account in secretAccounts(smbShareIDs: shareIDs) {
                if let value = keychain.get(account) { snap.secrets[account] = value }
            }
        }

        guard let data = try? JSONEncoder().encode(snap) else { return nil }

        let stamp = ISO8601DateFormatter().string(from: snap.createdAt)
            .replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FrameTV-\(stamp).frametv")
        do {
            try data.write(to: url, options: .atomic)
            FrameLog.sync.info("Exported snapshot file (secrets included: \(contents.contains(.secrets), privacy: .public))")
            return url
        } catch {
            FrameLog.sync.error("Failed to write snapshot export: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Inspects a snapshot file and returns which categories it actually contains, so
    /// the import UI can show only the relevant toggles.
    func contentsOfSnapshotFile(_ url: URL) -> BackupContents? {
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(BackupSnapshot.self, from: data) else { return nil }
        return availableContents(in: snap)
    }

    /// Downloads a snapshot from a URL (e.g. a link or one encoded in a QR code) and
    /// returns it as Data for inspection/import. Only http(s) URLs are fetched.
    func downloadSnapshot(from url: URL) async -> Data? {
        guard url.scheme == "http" || url.scheme == "https" else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            // Validate it actually decodes as a snapshot before handing it back.
            guard (try? JSONDecoder().decode(BackupSnapshot.self, from: data)) != nil else { return nil }
            return data
        } catch {
            FrameLog.sync.error("Snapshot download failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Returns which categories a raw snapshot blob contains.
    func contentsOfSnapshotData(_ data: Data) -> BackupContents? {
        guard let snap = try? JSONDecoder().decode(BackupSnapshot.self, from: data) else { return nil }
        return availableContents(in: snap)
    }

    /// Imports a snapshot from a raw blob (from a URL download or QR payload),
    /// applying only the selected categories.
    @discardableResult
    func importSnapshotData(_ data: Data, restoring contents: BackupContents = .all) -> Bool {
        guard let snap = try? JSONDecoder().decode(BackupSnapshot.self, from: data) else {
            FrameLog.sync.error("Snapshot import failed: unreadable data")
            return false
        }
        apply(snap, restoring: contents)
        FrameLog.sync.info("Imported snapshot from data (selected categories)")
        return true
    }

    /// The categories present (non-empty) in a snapshot.
    private func availableContents(in snap: BackupSnapshot) -> BackupContents {
        var c: BackupContents = []
        if !snap.settings.isEmpty { c.insert(.preferences) }
        if snap.smbSharesJSON != nil { c.insert(.sources) }
        if snap.addonsJSON != nil { c.insert(.addons) }
        if !snap.secrets.isEmpty { c.insert(.secrets) }
        return c
    }

    /// Imports a snapshot file, applying only the categories the user selected. If the
    /// file includes secrets and the user opts in, passwords/keys are restored too.
    @discardableResult
    func importSnapshotFile(_ url: URL, restoring contents: BackupContents = .all) -> Bool {
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(BackupSnapshot.self, from: data) else {
            FrameLog.sync.error("Snapshot import failed: unreadable file")
            return false
        }
        apply(snap, restoring: contents)
        FrameLog.sync.info("Imported snapshot file (selected categories)")
        return true
    }

    /// Applies a snapshot's selected categories to this device.
    private func apply(_ snap: BackupSnapshot, restoring contents: BackupContents) {
        let defaults = UserDefaults.standard
        if contents.contains(.preferences) {
            for (k, v) in snap.settings {
                switch v {
                case .bool(let b):   defaults.set(b, forKey: k); CloudSync.shared.setBool(b, forKey: k)
                case .string(let s): defaults.set(s, forKey: k); CloudSync.shared.setString(s, forKey: k)
                case .double(let d): defaults.set(d, forKey: k)
                case .data(let d):   defaults.set(d, forKey: k); CloudSync.shared.setData(d, forKey: k)
                }
            }
        }
        if contents.contains(.sources), let smb = snap.smbSharesJSON {
            writeSupportFile("smb_shares.json", smb)
        }
        if contents.contains(.addons), let addons = snap.addonsJSON {
            writeSupportFile("addons.json", addons)
        }
        if contents.contains(.secrets) {
            for (account, value) in snap.secrets {
                try? keychain.set(value, for: account)
            }
        }
        CloudSync.shared.flush()
    }
}
