//
//  RealSMBProvider.swift
//  Astra
//
//  A real SMB provider backed by the AMSMB2 library. Connects to user-configured
//  shares, lists directories, and serves files to AVPlayer through a small local
//  HTTP bridge (SMBStreamServer) that supports byte-range requests.
//
//  Credentials are pulled from the Keychain (never logged). This provider only
//  touches shares the user explicitly configured.
//

import Foundation
import AMSMB2

actor RealSMBProvider: SMBProviding {

    private var client: SMB2Manager?
    private var connectedShare: SMBShare?

    // MARK: - Connect

    func connect(to share: SMBShare) async throws {
        let host = share.host.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { throw SMBError.hostUnreachable }
        // 127.0.0.1 / localhost on the device points at the device itself, not the
        // user's computer — a common mistake. Catch it with a helpful message.
        let lowerHost = host.lowercased()
        if lowerHost == "127.0.0.1" || lowerHost == "localhost" || lowerHost == "::1" {
            throw SMBError.loopbackHost
        }
        guard let url = URL(string: "smb://\(host)") else { throw SMBError.hostUnreachable }

        // Credentials from Keychain (empty username => guest).
        let rawPassword = KeychainStore.shared.get(share.keychainAccount) ?? ""
        // Trim stray leading/trailing whitespace that a text field can capture, which
        // would make a correct-looking password fail authentication.
        let password = rawPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = share.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let connectUser = user.isEmpty ? "guest" : user

        if !user.isEmpty && password.isEmpty {
            throw SMBError.passwordMissing
        }

        let credential = URLCredential(user: connectUser, password: password, persistence: .forSession)

        guard let manager = SMB2Manager(url: url, credential: credential) else {
            throw SMBError.hostUnreachable
        }

        do {
            try await manager.connectShare(name: share.shareName)
        } catch {
            AstraLog.network.error("SMB connect failed for user length \(user.count, privacy: .public), password length \(password.count, privacy: .public): \(String(describing: error), privacy: .public)")
            throw mapError(error)
        }

        client = manager
        connectedShare = share
        AstraLog.network.info("Connected to SMB share \(share.shareName, privacy: .public)")
    }

    /// Connects to the server (no specific share) and lists its shares so the user
    /// can pick one — mirrors how the Files app shows shares under a server.
    func listShares(host: String, username: String, keychainAccount: String) async throws -> [String] {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw SMBError.hostUnreachable }
        let lowerHost = trimmed.lowercased()
        if lowerHost == "127.0.0.1" || lowerHost == "localhost" || lowerHost == "::1" {
            throw SMBError.loopbackHost
        }
        guard let url = URL(string: "smb://\(trimmed)") else { throw SMBError.hostUnreachable }

        let password = KeychainStore.shared.get(keychainAccount) ?? ""
        let user = username.isEmpty ? "guest" : username
        if !username.isEmpty && password.isEmpty {
            throw SMBError.passwordMissing
        }
        let credential = URLCredential(user: user, password: password, persistence: .forSession)
        guard let manager = SMB2Manager(url: url, credential: credential) else {
            throw SMBError.hostUnreachable
        }

        do {
            let shares = try await manager.listShares()
            // Filter out administrative/hidden shares ending in "$" (e.g. IPC$, C$).
            return shares.map(\.name).filter { !$0.hasSuffix("$") }
        } catch {
            throw mapError(error)
        }
    }

    // MARK: - List

    /// Retries an operation once after re-establishing the SMB session — a dropped
    /// connection (network change, NAS sleep) heals transparently instead of
    /// surfacing "not connected" to the browser.
    private func withReconnect<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            guard let share = connectedShare else { throw error }
            client = nil
            try await connect(to: share)
            return try await operation()
        }
    }

    func listDirectory(path: String) async throws -> [RemoteFileItem] {
        try await withReconnect { try await listDirectoryOnce(path: path) }
    }

    private func listDirectoryOnce(path: String) async throws -> [RemoteFileItem] {
        guard let client else { throw SMBError.notConnected }
        let smbPath = normalizedPath(path)

        // AMSMB2's async `contentsOfDirectory` returns `[[URLResourceKey: Any]]`,
        // which is non-Sendable and therefore can't cross back to this actor. Use
        // the completion-handler variant and reduce the raw attributes to Sendable
        // `RemoteFileItem`s inside the handler, so only Sendable data crosses the
        // continuation boundary.
        do {
            return try await withCheckedThrowingContinuation { continuation in
                client.contentsOfDirectory(atPath: smbPath) { result in
                    switch result {
                    case .success(let entries):
                        continuation.resume(returning: Self.mapEntries(entries, parentPath: smbPath))
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
        } catch {
            throw mapError(error)
        }
    }

    /// Reduces AMSMB2's raw `[URLResourceKey: Any]` attribute dictionaries to
    /// Sendable `RemoteFileItem`s. Static (hence nonisolated) so it can run inside
    /// the SMB library's completion handler without hopping onto the actor and
    /// without sending non-Sendable `Any` values across an isolation boundary.
    private static func mapEntries(_ entries: [[URLResourceKey: Any]], parentPath: String) -> [RemoteFileItem] {
        entries.compactMap { attrs -> RemoteFileItem? in
            guard let name = attrs[.nameKey] as? String else { return nil }
            if name == "." || name == ".." { return nil }

            let typeValue = attrs[.fileResourceTypeKey] as? URLFileResourceType
            let isDir = (typeValue == .directory)
            // Size may arrive as Int, Int64, or NSNumber depending on platform.
            let size: Int64?
            if let n = attrs[.fileSizeKey] as? Int64 { size = n }
            else if let n = attrs[.fileSizeKey] as? Int { size = Int64(n) }
            else if let n = attrs[.fileSizeKey] as? NSNumber { size = n.int64Value }
            else { size = nil }
            let modified = attrs[.contentModificationDateKey] as? Date

            let childPath = parentPath.isEmpty || parentPath == "/"
                ? "/\(name)"
                : "\(parentPath)/\(name)"

            return RemoteFileItem(
                name: name,
                path: childPath,
                isDirectory: isDir,
                size: isDir ? nil : size,
                modifiedDate: modified
            )
        }
        .sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory && !rhs.isDirectory }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    // MARK: - Stream

    func streamURL(for file: RemoteFileItem) async throws -> URL {
        guard let client, let share = connectedShare else { throw SMBError.notConnected }
        guard file.isPlayableVideo else { throw SMBError.streamingUnavailable }

        // Serve the SMB file over a local HTTP bridge that AVPlayer can read with
        // range requests.
        let url = try await SMBStreamServer.shared.serve(
            client: client,
            smbPath: normalizedPath(file.path),
            fileName: file.name,
            shareID: share.id
        )
        return url
    }

    // MARK: - Helpers

    private func normalizedPath(_ path: String) -> String {
        // AMSMB2 uses backslash-free, leading-slash-free relative paths.
        var p = path
        if p.hasPrefix("/") { p.removeFirst() }
        return p
    }

    private func mapError(_ error: Error) -> SMBError {
        let ns = error as NSError
        let desc = ns.localizedDescription.uppercased()

        // SMB/NT status codes are surfaced in the description text by AMSMB2.
        if desc.contains("LOGON_FAILURE") || desc.contains("ACCESS_DENIED")
            || desc.contains("WRONG_PASSWORD") || desc.contains("ACCOUNT") {
            return .authenticationFailed
        }
        if desc.contains("BAD_NETWORK_NAME") || desc.contains("OBJECT_NAME_NOT_FOUND") {
            return .pathNotFound
        }

        // POSIX/SMB error codes surfaced by AMSMB2.
        switch ns.code {
        case 13, 1:      return .authenticationFailed   // EACCES / EPERM
        case 2:          return .pathNotFound            // ENOENT
        case 61, 64, 65: return .hostUnreachable         // ECONNREFUSED / EHOSTDOWN / EHOSTUNREACH
        default:         return .underlying(error)
        }
    }
}
