//
//  KeychainStore.swift
//  Astra
//
//  Thin wrapper over the Security framework for storing secrets
//  (Real-Debrid token, SMB passwords). Values are never logged.
//

import Foundation
import Security

enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case dataConversionFailed

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Keychain operation failed (code \(status))."
        case .dataConversionFailed:
            return "Could not convert the value for secure storage."
        }
    }
}

/// A namespaced Keychain helper. All items share a service identifier so
/// they can be enumerated/cleared as a group.
struct KeychainStore {

    static let shared = KeychainStore()

    private let service = "com.frametv.app.secrets"

    // MARK: - Save / Update

    func set(_ value: String, for account: String) throws {
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
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    // MARK: - Delete

    func delete(_ account: String) throws {
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
