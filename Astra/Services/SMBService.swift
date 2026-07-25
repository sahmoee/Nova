//
//  SMBService.swift
//  Astra
//
//  Defines the SMBProviding protocol and a mock implementation used in
//  Phase 1/2. Phase 5 swaps in a real AMSMB2-backed provider behind the same
//  protocol — see the comment block at the bottom for the integration point.
//

import Foundation

// MARK: - Protocol

protocol SMBProviding: Sendable {
    func connect(to share: SMBShare) async throws
    func listShares(host: String, username: String, keychainAccount: String) async throws -> [String]
    func listDirectory(path: String) async throws -> [RemoteFileItem]
    func streamURL(for file: RemoteFileItem) async throws -> URL
}

// MARK: - Errors

enum SMBError: LocalizedError {
    case notConnected
    case authenticationFailed
    case passwordMissing
    case hostUnreachable
    case loopbackHost
    case pathNotFound
    case streamingUnavailable
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .notConnected:         return "Not connected to the SMB share."
        case .authenticationFailed: return "Sign-in was rejected. Use your computer account's user name (often your short name, like the one shown on your Mac login) and its exact password. For a Mac, make sure that account is allowed to share files."
        case .passwordMissing:      return "The saved password couldn't be read back. Remove this share and add it again. If it keeps happening, your device's Keychain may be blocking it."
        case .hostUnreachable:      return "Couldn't reach the SMB server. Check the name or IP and that the share is online."
        case .loopbackHost:         return "This share points to 127.0.0.1 (this device). Use your computer's network name (e.g. mycomputer.local) or its LAN IP address (e.g. 192.168.1.20) instead."
        case .pathNotFound:         return "That folder couldn't be found on the share."
        case .streamingUnavailable: return "This file can't be streamed directly from the share."
        case .underlying(let e):    return e.localizedDescription
        }
    }
}

// MARK: - Mock provider (Phase 1/2)

/// A deterministic, in-memory SMB provider so the UI is fully navigable before
/// the real SMB library is wired up. Returns a small folder tree of sample files.
actor MockSMBProvider: SMBProviding {

    private var connectedShare: SMBShare?

    func connect(to share: SMBShare) async throws {
        // Simulate latency.
        try? await Task.sleep(nanoseconds: 400_000_000)
        // Pretend an empty host is unreachable so error states are demoable.
        guard !share.host.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw SMBError.hostUnreachable
        }
        connectedShare = share
    }

    func listShares(host: String, username: String, keychainAccount: String) async throws -> [String] {
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !host.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw SMBError.hostUnreachable
        }
        return ["Movies", "TV Shows", "Backups"]
    }

    func listDirectory(path: String) async throws -> [RemoteFileItem] {
        guard connectedShare != nil else { throw SMBError.notConnected }
        try? await Task.sleep(nanoseconds: 300_000_000)

        let root = path.isEmpty || path == "/"
        if root {
            return [
                RemoteFileItem(name: "Movies", path: "/Movies", isDirectory: true),
                RemoteFileItem(name: "TV Shows", path: "/TV Shows", isDirectory: true),
                RemoteFileItem(name: "Home Videos", path: "/Home Videos", isDirectory: true),
                RemoteFileItem(name: "BigBuckBunny.mp4", path: "/BigBuckBunny.mp4",
                               isDirectory: false, size: 158_000_000,
                               modifiedDate: Date().addingTimeInterval(-86_400))
            ]
        }

        switch path {
        case "/Movies":
            return [
                RemoteFileItem(name: "Sintel.2010.1080p.mkv", path: "/Movies/Sintel.2010.1080p.mkv",
                               isDirectory: false, size: 740_000_000,
                               modifiedDate: Date().addingTimeInterval(-172_800)),
                RemoteFileItem(name: "TearsOfSteel.2012.720p.mp4", path: "/Movies/TearsOfSteel.2012.720p.mp4",
                               isDirectory: false, size: 410_000_000,
                               modifiedDate: Date().addingTimeInterval(-259_200))
            ]
        case "/TV Shows":
            return [
                RemoteFileItem(name: "Sample.S01E01.720p.mp4", path: "/TV Shows/Sample.S01E01.720p.mp4",
                               isDirectory: false, size: 220_000_000),
                RemoteFileItem(name: "Sample.S01E02.720p.mp4", path: "/TV Shows/Sample.S01E02.720p.mp4",
                               isDirectory: false, size: 224_000_000)
            ]
        case "/Home Videos":
            return [
                RemoteFileItem(name: "Vacation.mov", path: "/Home Videos/Vacation.mov",
                               isDirectory: false, size: 980_000_000)
            ]
        default:
            throw SMBError.pathNotFound
        }
    }

    func streamURL(for file: RemoteFileItem) async throws -> URL {
        guard connectedShare != nil else { throw SMBError.notConnected }
        guard file.isPlayableVideo else { throw SMBError.streamingUnavailable }
        // For the mock, hand back a public-domain test asset so playback actually works.
        return URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")!
    }
}

// MARK: - Service facade

/// Wraps whichever SMBProviding implementation is active and exposes a simple
/// API to the view models. Uses the real AMSMB2-backed provider; the mock remains
/// available for previews and tests by injecting it explicitly.
final class SMBService: Sendable {

    static let shared = SMBService()

    private let provider: SMBProviding

    init(provider: SMBProviding = RealSMBProvider()) {
        self.provider = provider
    }

    func connect(to share: SMBShare) async throws {
        try await provider.connect(to: share)
    }

    func listShares(host: String, username: String, keychainAccount: String) async throws -> [String] {
        try await provider.listShares(host: host, username: username, keychainAccount: keychainAccount)
    }

    func listDirectory(_ path: String) async throws -> [RemoteFileItem] {
        try await provider.listDirectory(path: path)
    }

    func streamURL(for file: RemoteFileItem) async throws -> URL {
        try await provider.streamURL(for: file)
    }
}
