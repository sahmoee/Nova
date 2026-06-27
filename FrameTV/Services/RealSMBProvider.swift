//
//  RealSMBProvider.swift
//  FrameTV
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
        guard let url = URL(string: "smb://\(host)") else { throw SMBError.hostUnreachable }

        guard let manager = SMB2Manager(url: url) else { throw SMBError.hostUnreachable }

        // Credentials from Keychain (empty username => guest).
        let password = KeychainStore.shared.get(share.keychainAccount) ?? ""
        let user = share.username.isEmpty ? "guest" : share.username

        do {
            try await manager.connectShare(name: share.shareName, user: user, password: password)
        } catch {
            // Map common failures to friendly errors.
            throw mapError(error)
        }

        client = manager
        connectedShare = share
        FrameLog.network.info("Connected to SMB share \(share.shareName, privacy: .public)")
    }

    // MARK: - List

    func listDirectory(path: String) async throws -> [RemoteFileItem] {
        guard let client else { throw SMBError.notConnected }
        let smbPath = normalizedPath(path)

        let entries: [[URLResourceKey: Any]]
        do {
            entries = try await client.contentsOfDirectory(atPath: smbPath)
        } catch {
            throw mapError(error)
        }

        return entries.compactMap { attrs -> RemoteFileItem? in
            guard let name = attrs[.nameKey] as? String else { return nil }
            if name == "." || name == ".." { return nil }

            let typeValue = attrs[.fileResourceTypeKey] as? URLFileResourceType
            let isDir = (typeValue == .directory)
            let size = (attrs[.fileSizeKey] as? NSNumber)?.int64Value
            let modified = attrs[.contentModificationDateKey] as? Date

            let childPath = smbPath.isEmpty || smbPath == "/"
                ? "/\(name)"
                : "\(smbPath)/\(name)"

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
        // POSIX/SMB error codes surfaced by AMSMB2.
        switch ns.code {
        case 13, 1:    return .authenticationFailed   // EACCES / EPERM
        case 2:        return .pathNotFound            // ENOENT
        case 61, 64, 65: return .hostUnreachable       // ECONNREFUSED / EHOSTDOWN / EHOSTUNREACH
        default:       return .underlying(error)
        }
    }
}
