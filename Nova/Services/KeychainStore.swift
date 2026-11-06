//
//  KeychainStore.swift
//  Nova
//
//  Thin wrapper over the Security framework for storing secrets
//  (Real-Debrid token, SMB passwords). Values are never logged.
//

import Foundation
import Security

enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case dataConversionFailed
    case itemNotFound

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Keychain operation failed (code \(status))."
        case .dataConversionFailed:
            return "Could not convert the value for secure storage."
        case .itemNotFound:
            return "No stored value was found for this account."
        }
    }
}

/// In-process cache of Keychain reads. On macOS the legacy file-based keychain is
/// slow (a single miss can scan the whole login keychain), and Settings reads several
/// secrets from inside SwiftUI view bodies, so uncached reads froze the Mac app's
/// Settings screen. Entries expire after a minute so changes that arrive through iCloud
/// Keychain still show up, and every local write or delete invalidates immediately.
private final class KeychainReadCache: @unchecked Sendable {
    static let shared = KeychainReadCache()
    private let lock = NSLock()
    private var entries: [String: (result: Result<String, KeychainError>, at: Date)] = [:]
    private let ttl: TimeInterval = 60

    func value(for key: String) -> Result<String, KeychainError>? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = entries[key], Date().timeIntervalSince(entry.at) < ttl else { return nil }
        return entry.result
    }

    func store(_ result: Result<String, KeychainError>, for key: String) {
        // Only cache definitive answers, never transient failures.
        switch result {
        case .success, .failure(.itemNotFound): break
        default: return
        }
        lock.lock(); defer { lock.unlock() }
        entries[key] = (result, Date())
    }

    func invalidate(_ key: String) {
        lock.lock(); defer { lock.unlock() }
        entries[key] = nil
    }

    func invalidateAll() {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll()
    }
}

/// A namespaced Keychain helper. All items share a service identifier so
/// they can be enumerated/cleared as a group.
struct KeychainStore {

    static let shared = KeychainStore()

    // Nova's Keychain service identifier (single source of truth).
    private let service = NovaIdentifiers.keychainService

    // MARK: - Save / Update

    func set(_ value: String, for account: String) throws {
        defer { KeychainReadCache.shared.invalidate(service + "|" + account) }
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.dataConversionFailed
        }

        // Prefer a synchronizable item so secrets sync via iCloud Keychain. If that
        // fails (e.g. iCloud Keychain disabled), fall back to a local-only item so
        // the secret is never silently lost — a lost SMB password otherwise looks
        // exactly like a wrong password at connect time.
        do {
            try write(data, account: account, synchronizable: true)
        } catch {
            try write(data, account: account, synchronizable: false)
        }
    }

    private func write(_ data: Data, account: String, synchronizable: Bool) throws {
        let syncValue: Any = synchronizable ? (kCFBooleanTrue as Any) : (kCFBooleanFalse as Any)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: syncValue
        ]

        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    // MARK: - Read

    func get(_ account: String) -> String? {
        try? getResult(account).get()
    }

    /// Result-returning read that distinguishes "missing" from "broken" instead of
    /// collapsing both to nil, so callers can log or surface real Keychain failures
    /// (corruption, entitlement issues) rather than silently treating them as unset.
    func getResult(_ account: String) -> Result<String, KeychainError> {
        let cacheKey = service + "|" + account
        if let cached = KeychainReadCache.shared.value(for: cacheKey) { return cached }
        let result = readUncached(account)
        KeychainReadCache.shared.store(result, for: cacheKey)
        return result
    }

    private func readUncached(_ account: String) -> Result<String, KeychainError> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny as Any,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let value = String(data: data, encoding: .utf8) else {
                return .failure(.dataConversionFailed)
            }
            return .success(value)
        case errSecItemNotFound:
            return .failure(.itemNotFound)
        default:
            return .failure(.unexpectedStatus(status))
        }
    }

    // MARK: - Delete

    func delete(_ account: String) throws {
        defer { KeychainReadCache.shared.invalidate(service + "|" + account) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny as Any
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Removes every secret stored by this app under our service identifier.
    func deleteAll() throws {
        defer { KeychainReadCache.shared.invalidateAll() }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny as Any
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Convenience for the Real-Debrid token

    static let realDebridTokenAccount = "realdebrid.token"

    var realDebridToken: String? {
        get { get(Self.realDebridTokenAccount) }
    }

    func setRealDebridToken(_ token: String) throws {
        try set(token, for: Self.realDebridTokenAccount)
    }

    func clearRealDebridToken() throws {
        try delete(Self.realDebridTokenAccount)
    }
}
