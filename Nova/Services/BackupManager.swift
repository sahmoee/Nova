//
//  BackupManager.swift
//  Nova
//
//  Creates a single "snapshot" that captures everything needed to reproduce the
//  user's setup on another device: preferences, SMB sources (with passwords), Live
//  TV playlists (with any logins), installed addons, and all accounts / API keys /
//  tokens from the Keychain. The snapshot is stored in iCloud key-value storage so
//  it follows the user's Apple ID, and can be restored manually or offered
//  automatically on a fresh install.
//
//  Snapshots are platform-neutral JSON, so a snapshot written on iPhone, iPad, or
//  Apple TV restores on any of the others. Every field is optional, so snapshots
//  stay forward and backward compatible across app versions.
//
//  Secrets are included because the whole point is to move logins between the
//  user's own devices via their private iCloud. The snapshot lives only in the
//  user's iCloud KVS, never leaves Apple's sync, and is not written anywhere else.
//

import Foundation
import CryptoKit
#if os(iOS)
import UIKit
#endif

/// Distinguishes a Bool stored in UserDefaults from a numeric value. UserDefaults
/// bridges both to NSNumber, so this checks the underlying CoreFoundation type.
/// Broadcast after a backup snapshot's data has been written to disk / Keychain /
/// UserDefaults, so live in-memory stores (Live TV sources, Trakt, addons, SMB)
/// reload the restored state instead of keeping the stale values they loaded at
/// launch. Without this, a restore "shows as there but doesn't work": the files on
/// disk are correct but the running stores never re-read them. The userInfo carries
/// the restored BackupContents rawValue under "contents".
extension Notification.Name {
    static let novaBackupRestored = Notification.Name("nova.backupRestored")
}

private extension NSNumber {
    var isBool: Bool { CFGetTypeID(self) == CFBooleanGetTypeID() }
}

// MARK: - Snapshot model

struct BackupSnapshot: Codable, Equatable {
    // v2 adds liveTVJSON. Older apps ignore unknown/optional fields, and this app
    // treats every snapshot field as optional, so v1 and v2 snapshots restore on
    // any device (iPhone, iPad, Apple TV) regardless of which version wrote them.
    var version: Int = 2
    var createdAt: Date = Date()
    var deviceName: String = ""

    /// Non-secret preference key/values mirrored from iCloud KVS / UserDefaults.
    var settings: [String: BackupValue] = [:]
    /// Raw JSON for SMB shares, addons, and Live TV sources (as stored locally).
    var smbSharesJSON: Data?
    var addonsJSON: Data?
    var liveTVJSON: Data?
    /// Keychain secrets: account -> value. Includes API keys, tokens, and the
    /// per-share SMB passwords (accounts of the form "smb.<uuid>").
    var secrets: [String: String] = [:]

    private enum CodingKeys: String, CodingKey {
        case version, createdAt, deviceName, settings
        case smbSharesJSON, addonsJSON, liveTVJSON, secrets
    }

    init() {}

    /// Early v1 snapshots predate some fields. Decode missing
    /// values defensively so a valid older snapshot never fails just because a
    /// newer Nova field did not exist when it was written.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
        deviceName = try values.decodeIfPresent(String.self, forKey: .deviceName) ?? "Legacy device"
        settings = try values.decodeIfPresent([String: BackupValue].self, forKey: .settings) ?? [:]
        smbSharesJSON = try values.decodeIfPresent(Data.self, forKey: .smbSharesJSON)
        addonsJSON = try values.decodeIfPresent(Data.self, forKey: .addonsJSON)
        liveTVJSON = try values.decodeIfPresent(Data.self, forKey: .liveTVJSON)
        secrets = try values.decodeIfPresent([String: String].self, forKey: .secrets) ?? [:]
    }
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
             detail: "Your SMB network shares and Live TV playlists (addresses and usernames).",
             systemImage: "externaldrive.connected.to.line.below", sensitive: false),
        Item(option: .addons, title: "Addons",
             detail: "Installed addon catalogs and their configuration.",
             systemImage: "puzzlepiece.extension", sensitive: false),
        Item(option: .secrets, title: "Logins & API keys",
             detail: "All accounts, passwords, tokens, and API keys (Trakt, Real-Debrid, TMDB, OpenSubtitles, OMDb, SMB and Live TV passwords). Only share with people you trust.",
             systemImage: "key.fill", sensitive: true)
    ]
}

/// A small sum type so we can round-trip the handful of value kinds in settings.
enum BackupValue: Codable, Equatable {
    case bool(Bool)
    case string(String)
    case double(Double)
    case data(Data)
}

// MARK: - Backup origin

enum BackupOrigin: String, Equatable {
    case nova
    /// A snapshot whose schema predates the current writer marker; shown generically.
    case imported

    var displayName: String {
        switch self {
        case .nova: return "Nova"
        case .imported: return "an earlier version"
        }
    }

    var isLegacy: Bool { self != .nova }
}

struct DecodedBackupSnapshot {
    var snapshot: BackupSnapshot
    var origin: BackupOrigin
    var wasNormalized: Bool
}

enum BackupCompatibility {
    // The stable production key for the snapshot in iCloud KVS. Duplicating the
    // snapshot under a second key would waste KVS's 1 MB total budget.
    static let currentCloudKey = "backup.snapshot.v1"
    static let writerCloudKey = "backup.snapshot.writer"
    static let supportedFileExtensions = ["nova", "json"]

    static func decode(_ data: Data,
                       fileName: String? = nil,
                       defaultOrigin: BackupOrigin = .nova) throws -> DecodedBackupSnapshot {
        let original = try JSONDecoder().decode(BackupSnapshot.self, from: data)
        let snapshot = normalize(original)
        return DecodedBackupSnapshot(
            snapshot: snapshot,
            origin: origin(fileName: fileName, snapshotVersion: snapshot.version) ?? defaultOrigin,
            wasNormalized: snapshot != original
        )
    }

    static func origin(fileName: String?, snapshotVersion: Int) -> BackupOrigin? {
        guard let fileName else { return snapshotVersion <= 1 ? .imported : nil }
        let lower = fileName.lowercased()
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        if ext == "nova" || lower.hasPrefix("nova-") { return .nova }
        return snapshotVersion <= 1 ? .imported : nil
    }

    /// Passes settings and JSON blobs through the normalizer. Account values and
    /// secrets are deliberately untouched.
    static func normalize(_ input: BackupSnapshot) -> BackupSnapshot {
        var output = input
        output.settings = input.settings.mapValues { value in
            switch value {
            case .string(let string): return .string(normalizeURLScheme(in: string))
            case .data(let data): return .data(normalizeJSONData(data))
            case .bool, .double: return value
            }
        }
        output.smbSharesJSON = input.smbSharesJSON.map(normalizeJSONData)
        output.addonsJSON = input.addonsJSON.map(normalizeJSONData)
        output.liveTVJSON = input.liveTVJSON.map(normalizeJSONData)
        return output
    }

    static func normalizeURLScheme(in string: String) -> String {
        // Nova is the only supported deep-link scheme; nothing to rewrite.
        string
    }

    static func normalizeJSONData(_ data: Data) -> Data {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return data
        }
        let (normalized, changed) = normalizeJSONObject(object)
        guard changed else { return data }
        return (try? JSONSerialization.data(
            withJSONObject: normalized,
            options: [.fragmentsAllowed, .sortedKeys]
        )) ?? data
    }

    private static func normalizeJSONObject(_ object: Any) -> (value: Any, changed: Bool) {
        switch object {
        case let string as String:
            let normalized = normalizeURLScheme(in: string)
            return (normalized, normalized != string)
        case let array as [Any]:
            var changed = false
            let normalized = array.map { value -> Any in
                let result = normalizeJSONObject(value)
                changed = changed || result.changed
                return result.value
            }
            return (normalized, changed)
        case let dictionary as [String: Any]:
            var changed = false
            let normalized = dictionary.mapValues { value -> Any in
                let result = normalizeJSONObject(value)
                changed = changed || result.changed
                return result.value
            }
            return (normalized, changed)
        default:
            return (object, false)
        }
    }
}

// MARK: - Manager

@MainActor
final class BackupManager: ObservableObject {

    static let shared = BackupManager()

    @Published private(set) var lastBackupDate: Date?
    @Published private(set) var lastBackupOrigin: BackupOrigin?
    private let lastAutoSyncKey = "backup.lastAutoSyncedSnapshot"

    private let keychain = KeychainStore.shared

    // FIX: one shared formatter instead of allocating a fresh ISO8601DateFormatter
    // at three call sites (auto-sync stamp, export filename, share-code expiry).
    // ISO8601DateFormatter is expensive to create and thread-safe to reuse. It isn't
    // `Sendable`, and this instance is never reconfigured, so opt out of the
    // concurrency check the same way the app does for other shared statics.
    nonisolated(unsafe) private static let isoFormatter = ISO8601DateFormatter()

    init() {
        if let decoded = loadSnapshotRecordFromCloud() {
            lastBackupDate = decoded.snapshot.createdAt
            lastBackupOrigin = decoded.origin
        }
    }

    // MARK: - Settings keys to capture

    /// JSON-backed preference blobs stored in UserDefaults (not in a support file).
    /// These are captured explicitly because dictionaryRepresentation surfaces them as
    /// Data, which the prefix scan also handles, but listing them documents intent.
    private let settingDataKeys = [
        "home.shelves.v1",                       // customized home/discover shelves
        "stream.history.v1",                     // last-used stream per movie/episode
        "reco.feedback.v1"                       // recommendation feedback (hidden/genres)
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
        // Live TV sources (with any usernames/passwords) go in full — the iCloud
        // snapshot lives only in the user's private iCloud.
        snap.liveTVJSON = liveTVJSON()

        // Secrets from Keychain.
        let shareIDs = smbShareIDs(from: snap.smbSharesJSON)
        for account in secretAccounts(smbShareIDs: shareIDs) {
            if let value = keychain.get(account) {
                snap.secrets[account] = value
            }
        }

        // Persist to iCloud.
        if let data = try? JSONEncoder().encode(snap) {
            // Write the stable production key plus a tiny marker recording the writer.
            CloudSync.shared.setData(data, forKey: BackupCompatibility.currentCloudKey)
            CloudSync.shared.setString(BackupOrigin.nova.rawValue,
                                       forKey: BackupCompatibility.writerCloudKey)
            CloudSync.shared.flush()
            lastBackupDate = snap.createdAt
            lastBackupOrigin = .nova
            NovaLog.sync.info("Created backup snapshot (\(snap.secrets.count) secrets)")
        }
    }

    // MARK: - Restore

    /// Whether a snapshot exists in iCloud that could be restored.
    func hasCloudSnapshot() -> Bool { loadSnapshotFromCloud() != nil }

    /// Returns metadata about the available snapshot for confirmation UI.
    func availableSnapshotInfo() -> (date: Date, device: String, origin: BackupOrigin)? {
        guard let decoded = loadSnapshotRecordFromCloud() else { return nil }
        return (decoded.snapshot.createdAt, decoded.snapshot.deviceName, decoded.origin)
    }

    /// Applies a newer iCloud snapshot from the user's other devices silently on
    /// launch and foreground, so preferences, sources, and addons follow them across
    /// iPhone, iPad, and Apple TV. Secrets stay opt in. Applied at most once per
    /// snapshot per device. Returns true if anything was applied.
    @discardableResult
    func autoSyncOnLaunch() -> Bool {
        CloudSync.shared.pull()
        guard let snap = loadSnapshotFromCloud() else { return false }
        let defaults = UserDefaults.standard
        let stamp = Self.isoFormatter.string(from: snap.createdAt)
        if snap.deviceName == deviceName(), defaults.string(forKey: lastAutoSyncKey) == nil {
            defaults.set(stamp, forKey: lastAutoSyncKey)
            return false
        }
        if defaults.string(forKey: lastAutoSyncKey) == stamp { return false }
        let contents = availableContents(in: snap).subtracting(.secrets)
        guard !contents.isEmpty else {
            defaults.set(stamp, forKey: lastAutoSyncKey)
            return false
        }
        apply(snap, restoring: contents)
        defaults.set(stamp, forKey: lastAutoSyncKey)
        return true
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
        if contents.contains(.sources), let data = snap.liveTVJSON {
            CloudSync.shared.setData(data, forKey: LiveTVSourceStore.cloudKey)
        }
        if contents.contains(.addons), let data = snap.addonsJSON {
            CloudSync.shared.setData(data, forKey: "cloud.addons")
        }
        CloudSync.shared.flush()
        NovaLog.sync.info("Restored backup snapshot from \(snap.deviceName, privacy: .public)")
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
        if readSupportFile("smb_shares.json") != nil || liveTVJSON() != nil { c.insert(.sources) }
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
        loadSnapshotRecordFromCloud()?.snapshot
    }

    /// Reads the stable production key and records the writer marker if absent.
    private func loadSnapshotRecordFromCloud() -> DecodedBackupSnapshot? {
        let cloud = CloudSync.shared
        if let data = cloud.data(forKey: BackupCompatibility.currentCloudKey) {
            let recordedOrigin = cloud.string(forKey: BackupCompatibility.writerCloudKey)
                .flatMap(BackupOrigin.init(rawValue:))
            if let decoded = try? BackupCompatibility.decode(
                data,
                defaultOrigin: recordedOrigin ?? .imported
            ) {
                if recordedOrigin == nil {
                    cloud.setString(decoded.origin.rawValue,
                                    forKey: BackupCompatibility.writerCloudKey)
                }
                if decoded.wasNormalized,
                   let normalized = try? JSONEncoder().encode(decoded.snapshot) {
                    cloud.setData(normalized, forKey: BackupCompatibility.currentCloudKey)
                    cloud.flush()
                    NovaLog.sync.info("Normalized an imported iCloud snapshot")
                }
                return decoded
            }
        }
        return nil
    }

    private func smbShareIDs(from json: Data?) -> [UUID] {
        guard let json,
              let shares = try? JSONDecoder().decode([SMBShare].self, from: json) else { return [] }
        return shares.map { $0.id }
    }

    /// The current Live TV source list as JSON, read straight from its iCloud KVS
    /// mirror (falling back to the local UserDefaults copy). Only user-added sources
    /// are worth moving; built-ins are re-seeded on every device anyway, but keeping
    /// them is harmless and keeps the blob self-contained.
    private func liveTVJSON() -> Data? {
        if let data = CloudSync.shared.data(forKey: LiveTVSourceStore.cloudKey) { return data }
        return UserDefaults.standard.data(forKey: "livetv.sources.v1")
    }

    /// Returns a copy of a Live TV source JSON blob with any embedded usernames and
    /// passwords removed, so the source list can travel without its logins when the
    /// user hasn't opted into including secrets.
    private func liveTVJSONStrippingCredentials(_ data: Data?) -> Data? {
        guard let data,
              var sources = try? JSONDecoder().decode([LiveTVSource].self, from: data) else { return data }
        for i in sources.indices {
            sources[i].username = nil
            sources[i].password = nil
        }
        return try? JSONEncoder().encode(sources)
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

    /// Builds a snapshot of the current setup and writes it to a temporary .nova
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
            // Live TV goes with the sources category. Its embedded usernames and
            // passwords are only kept when the user also opts into secrets.
            let liveTV = liveTVJSON()
            snap.liveTVJSON = contents.contains(.secrets)
                ? liveTV
                : liveTVJSONStrippingCredentials(liveTV)
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

        let stamp = Self.isoFormatter.string(from: snap.createdAt)
            .replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Nova-\(stamp).nova")
        do {
            try data.write(to: url, options: .atomic)
            NovaLog.sync.info("Exported snapshot file (secrets included: \(contents.contains(.secrets), privacy: .public))")
            return url
        } catch {
            NovaLog.sync.error("Failed to write snapshot export: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Builds the encoded snapshot blob for the chosen categories (the same content
    /// rules as the shareable file, including credential stripping when secrets are
    /// not opted in). Shared by file export and code sharing.
    private func buildSnapshotData(including contents: BackupContents) -> Data? {
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
            let liveTV = liveTVJSON()
            snap.liveTVJSON = contents.contains(.secrets)
                ? liveTV
                : liveTVJSONStrippingCredentials(liveTV)
        }
        if contents.contains(.addons) {
            snap.addonsJSON = readSupportFile("addons.json")
        }
        if contents.contains(.secrets) {
            let shareIDs = smbShareIDs(from: snap.smbSharesJSON ?? readSupportFile("smb_shares.json"))
            for account in secretAccounts(smbShareIDs: shareIDs) {
                if let value = keychain.get(account) { snap.secrets[account] = value }
            }
        }
        return try? JSONEncoder().encode(snap)
    }

    // MARK: - Share via code (peer-to-peer, via the Worker)

    /// The result of creating a share code.
    struct ShareCodeResult {
        let code: String
        let expiresAt: Date?
    }

    private struct ShareCreateResponse: Decodable { let code: String; let expiresAt: String? }
    private struct ShareFetchResponse: Decodable { let snapshot: String; let contents: Int?; let enc: Bool? }

    /// The Worker base URL, reused from the AI Search configuration.
    private var shareWorkerURL: URL? { AISearchService.workerURL }

    /// Whether code sharing can be used (the Worker URL is configured).
    var canShareViaCode: Bool { shareWorkerURL != nil }

    /// Uploads a snapshot (with the chosen categories) to the Worker and returns a
    /// short code another person can enter to restore it. Nil on failure.
    func createShareCode(including contents: BackupContents,
                         ttlDays: Int = 7) async -> ShareCodeResult? {
        guard let base = shareWorkerURL,
              let data = buildSnapshotData(including: contents) else { return nil }
        let url = NovaWorkerConfiguration.endpoint(base: base, path: NovaIdentifiers.WorkerPath.shareCreate)
        // Encrypt on-device (AES-GCM). The Worker only ever stores ciphertext; the
        // decryption key travels inside the share code, never to the server.
        let key = SymmetricKey(size: .bits256)
        guard let sealed = try? AES.GCM.seal(data, using: key), let combined = sealed.combined else {
            return nil
        }
        let payload: [String: Any] = [
            "snapshot": combined.base64EncodedString(),
            "contents": contents.rawValue,
            "enc": true,
            "ttlDays": ttlDays
        ]
        do {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            for (k, v) in AISearchService.authHeaders { req.setValue(v, forHTTPHeaderField: k) }
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)
            req.timeoutInterval = 30
            let (respData, response) = try await AppNetworking.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                NovaLog.sync.error("Share create failed (bad status)")
                return nil
            }
            let decoded = try JSONDecoder().decode(ShareCreateResponse.self, from: respData)
            let expires = decoded.expiresAt.flatMap { Self.isoFormatter.date(from: $0) }
            // Full share code = lookup code + "~" + base64(key). The "~" separator is
            // outside the base64 alphabet, and the lookup code is A-Z0-9 only.
            let keyB64 = key.withUnsafeBytes { Data($0) }.base64EncodedString()
            let fullCode = "\(decoded.code.uppercased())~\(keyB64)"
            NovaLog.sync.info("Created encrypted share code")
            return ShareCodeResult(code: fullCode, expiresAt: expires)
        } catch {
            NovaLog.sync.error("Share create error: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Fetches a shared snapshot by code from the Worker. Returns the raw snapshot
    /// Data (ready for contentsOfSnapshotData / importSnapshotData), or nil.
    func fetchSharedSnapshot(code: String) async -> Data? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let base = shareWorkerURL, !trimmed.isEmpty else { return nil }
        // Split "<lookup>~<base64 key>". Uppercase ONLY the lookup part (the key is
        // case-sensitive base64).
        let parts = trimmed.split(separator: "~", maxSplits: 1, omittingEmptySubsequences: false)
        let lookup = String(parts[0]).uppercased()
        let keyB64 = parts.count > 1 ? String(parts[1]) : nil
        let url = NovaWorkerConfiguration.endpoint(base: base, path: NovaIdentifiers.WorkerPath.shareFetch)
        do {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            for (k, v) in AISearchService.authHeaders { req.setValue(v, forHTTPHeaderField: k) }
            req.httpBody = try JSONSerialization.data(withJSONObject: ["code": lookup])
            req.timeoutInterval = 30
            let (respData, response) = try await AppNetworking.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                NovaLog.sync.error("Share fetch failed (bad status)")
                return nil
            }
            let decoded = try JSONDecoder().decode(ShareFetchResponse.self, from: respData)
            guard let blob = Data(base64Encoded: decoded.snapshot) else { return nil }
            // Encrypted payload: decrypt with the key from the code. If the key is
            // missing we can't recover it — fail rather than returning ciphertext.
            if decoded.enc == true {
                guard let keyB64, let keyData = Data(base64Encoded: keyB64),
                      let box = try? AES.GCM.SealedBox(combined: blob),
                      let plain = try? AES.GCM.open(box, using: SymmetricKey(data: keyData)) else {
                    NovaLog.sync.error("Share fetch: decryption failed (bad or missing key)")
                    return nil
                }
                return plain
            }
            return blob  // legacy unencrypted snapshot
        } catch {
            NovaLog.sync.error("Share fetch error: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Inspects a snapshot file and returns which categories it actually contains, so
    /// the import UI can show only the relevant toggles.
    func contentsOfSnapshotFile(_ url: URL) -> BackupContents? {
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let decoded = try? BackupCompatibility.decode(data, fileName: url.lastPathComponent) else {
            return nil
        }
        return availableContents(in: decoded.snapshot)
    }

    /// Downloads a snapshot from a URL (e.g. a link or one encoded in a QR code) and
    /// returns it as Data for inspection/import. Only http(s) URLs are fetched.
    func downloadSnapshot(from url: URL) async -> Data? {
        guard url.scheme == "http" || url.scheme == "https" else { return nil }
        do {
            let (data, response) = try await AppNetworking.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            // Validate it actually decodes as a snapshot before handing it back.
            guard (try? BackupCompatibility.decode(data, fileName: url.lastPathComponent)) != nil else {
                return nil
            }
            return data
        } catch {
            NovaLog.sync.error("Snapshot download failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Returns which categories a raw snapshot blob contains.
    func contentsOfSnapshotData(_ data: Data) -> BackupContents? {
        guard let decoded = try? BackupCompatibility.decode(data) else { return nil }
        return availableContents(in: decoded.snapshot)
    }

    /// Imports a snapshot from a raw blob (from a URL download or QR payload),
    /// applying only the selected categories.
    @discardableResult
    func importSnapshotData(_ data: Data, restoring contents: BackupContents = .all) -> Bool {
        guard let decoded = try? BackupCompatibility.decode(data) else {
            NovaLog.sync.error("Snapshot import failed: unreadable data")
            return false
        }
        apply(decoded.snapshot, restoring: contents)
        NovaLog.sync.info("Imported \(decoded.origin.displayName, privacy: .public) snapshot from data")
        return true
    }

    /// The categories present (non-empty) in a snapshot.
    private func availableContents(in snap: BackupSnapshot) -> BackupContents {
        var c: BackupContents = []
        if !snap.settings.isEmpty { c.insert(.preferences) }
        if snap.smbSharesJSON != nil || snap.liveTVJSON != nil { c.insert(.sources) }
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
              let decoded = try? BackupCompatibility.decode(data, fileName: url.lastPathComponent) else {
            NovaLog.sync.error("Snapshot import failed: unreadable file")
            return false
        }
        apply(decoded.snapshot, restoring: contents)
        NovaLog.sync.info("Imported \(decoded.origin.displayName, privacy: .public) snapshot file")
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
        if contents.contains(.sources), let liveTV = snap.liveTVJSON {
            // Restore Live TV both locally and to its iCloud mirror so the store
            // and every other device converge on it.
            UserDefaults.standard.set(liveTV, forKey: "livetv.sources.v1")
            CloudSync.shared.setData(liveTV, forKey: LiveTVSourceStore.cloudKey)
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

        // Tell the running stores to reload the freshly-restored data. Everything
        // above only touched disk/Keychain/iCloud; the live objects still hold what
        // they loaded at launch until they hear this.
        NotificationCenter.default.post(
            name: .novaBackupRestored,
            object: nil,
            userInfo: ["contents": contents.rawValue]
        )
    }
}
