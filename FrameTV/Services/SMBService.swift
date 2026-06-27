//
//  SMBService.swift
//  FrameTV
//
//  Defines the SMBProviding protocol and a mock implementation used in
//  Phase 1/2. Phase 5 swaps in a real AMSMB2-backed provider behind the same
//  protocol — see the comment block at the bottom for the integration point.
//

import Foundation

// MARK: - Protocol

protocol SMBProviding: Sendable {
    func connect(to share: SMBShare) async throws
    func listDirectory(path: String) async throws -> [RemoteFileItem]
    func streamURL(for file: RemoteFileItem) async throws -> URL
}

// MARK: - Errors

enum SMBError: LocalizedError {
    case notConnected
    case authenticationFailed
    case hostUnreachable
    case pathNotFound
    case streamingUnavailable
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .notConnected:         return "Not connected to the SMB share."
        case .authenticationFailed: return "SMB sign-in failed. Check the username and password."
        case .hostUnreachable:      return "Couldn't reach the SMB server. Check the name or IP and that the share is online."
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
/// API to the view models. Defaults to the mock provider.
final class SMBService {

    static let shared = SMBService()

    private let provider: SMBProviding

    init(provider: SMBProviding = MockSMBProvider()) {
        self.provider = provider
    }

    func connect(to share: SMBShare) async throws {
        try await provider.connect(to: share)
    }

    func listDirectory(_ path: String) async throws -> [RemoteFileItem] {
        try await provider.listDirectory(path: path)
    }

    func streamURL(for file: RemoteFileItem) async throws -> URL {
        try await provider.streamURL(for: file)
    }
}

//
// ─────────────────────────────────────────────────────────────────────────────
//  PHASE 5 — REAL SMB INTEGRATION (add the AMSMB2 Swift package, then implement)
//
//  1. In Xcode: File ▸ Add Package Dependencies…
//     URL: https://github.com/amosavian/AMSMB2
//     Add the "AMSMB2" product to the FrameTV tvOS target.
//
//  2. Create `RealSMBProvider: SMBProviding` that:
//       - builds an `SMB2Manager` with the share URL (smb://host/share)
//       - authenticates with username + password pulled from KeychainStore
//         (account == share.keychainAccount)
//       - maps AMSMB2 directory entries to RemoteFileItem
//       - for streamURL, either returns a direct smb URL if AVPlayer can read it,
//         or starts the progressive local streaming bridge described below.
//
//  3. Switch the active provider:
//       SMBService(provider: RealSMBProvider())
//
//  PROGRESSIVE LOCAL STREAMING BRIDGE (only for user-owned network files):
//       - Spin up a tiny local HTTP server (e.g. on 127.0.0.1) that reads bytes
//         from the SMB file on demand and serves them with Range support.
//       - Hand AVPlayer the http://127.0.0.1:<port>/… URL.
//       - Keep the on-disk cache minimal/temporary; purge on playback end.
// ─────────────────────────────────────────────────────────────────────────────
//
