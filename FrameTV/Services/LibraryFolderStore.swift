//
//  LibraryFolderStore.swift
//  FrameTV
//
//  Lets the user register folder locations (currently SMB shares/paths) whose video
//  files are scanned and added to the library, so a NAS folder of movies shows up in
//  My Library without browsing to it each time.
//

import Foundation

/// A saved library folder: an SMB share plus an optional sub-path to scan. Rescanning
/// walks the folder (recursively, up to a depth limit) and adds every video file found.
struct LibraryFolder: Identifiable, Codable, Hashable {
    var id: UUID
    /// The SMB share this folder lives on.
    var shareID: UUID
    /// Human-readable label shown in Settings.
    var displayName: String
    /// The folder path within the share to scan (for example "/Movies"). Empty scans
    /// the share root.
    var path: String
    /// When the folder was last scanned, if ever.
    var lastScanned: Date?
    /// How many items were added on the last scan.
    var lastAddedCount: Int

    init(id: UUID = UUID(), shareID: UUID, displayName: String, path: String,
         lastScanned: Date? = nil, lastAddedCount: Int = 0) {
        self.id = id
        self.shareID = shareID
        self.displayName = displayName
        self.path = path
        self.lastScanned = lastScanned
        self.lastAddedCount = lastAddedCount
    }
}

/// Stores the user's registered library folders and rescans them into the library.
@MainActor
final class LibraryFolderStore: ObservableObject {
    @Published private(set) var folders: [LibraryFolder] = []
    /// The folder currently being scanned, if any (for progress UI).
    @Published var scanningFolderID: UUID?
    /// A human-readable status for the in-progress scan.
    @Published var scanStatus: String?

    private let defaultsKey = "library.folders.v1"
    private let defaults = UserDefaults.standard

    /// The maximum directory depth walked during a scan, so a huge tree can't hang the
    /// app. Most media libraries are only two or three levels deep.
    private let maxDepth = 4

    init() {
        load()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([LibraryFolder].self, from: data) else { return }
        folders = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(folders) {
            defaults.set(data, forKey: defaultsKey)
        }
    }

    // MARK: - Managing folders

    func addFolder(shareID: UUID, displayName: String, path: String) -> LibraryFolder {
        let normalized = path.hasPrefix("/") || path.isEmpty ? path : "/" + path
        let folder = LibraryFolder(shareID: shareID, displayName: displayName, path: normalized)
        folders.append(folder)
        persist()
        return folder
    }

    func removeFolder(_ folder: LibraryFolder) {
        folders.removeAll { $0.id == folder.id }
        persist()
    }

    // MARK: - Scanning

    /// Reads the SMB shares the user has configured (from the same support file
    /// SMBSharesModel persists), so a folder can resolve its share without extra wiring.
    private func loadShares() -> [SMBShare] {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let url = support?.appendingPathComponent("smb_shares.json"),
              let data = try? Data(contentsOf: url),
              let shares = try? JSONDecoder().decode([SMBShare].self, from: data) else { return [] }
        return shares
    }

    /// The SMB shares available to attach a library folder to.
    var availableShares: [SMBShare] { loadShares() }

    /// Rescans a single folder, adding every video file found (recursively) to the
    /// library. Files already present are skipped by their stable content key, so a
    /// rescan is safe to run repeatedly. Returns the number of newly added items.
    @discardableResult
    func rescan(_ folder: LibraryFolder, using env: AppEnvironment) async -> Int {
        guard let share = loadShares().first(where: { $0.id == folder.shareID }) else {
            scanStatus = "This folder's share is no longer configured."
            return 0
        }

        scanningFolderID = folder.id
        scanStatus = "Connecting…"
        defer { scanningFolderID = nil; scanStatus = nil }

        do {
            try await env.smb.connect(to: share)
        } catch {
            scanStatus = "Couldn't connect to \(share.displayName)."
            return 0
        }

        var videos: [RemoteFileItem] = []
        await walk(path: folder.path.isEmpty ? "/" : folder.path,
                   depth: 0, env: env, into: &videos)

        var added = 0
        for (index, file) in videos.enumerated() {
            scanStatus = "Adding \(index + 1) of \(videos.count)…"
            if let item = try? await makeItem(for: file, env: env) {
                let key = item.contentKey
                if !env.library.items.contains(where: { $0.contentKey == key }) {
                    env.library.add(item)
                    added += 1
                }
            }
        }

        // Record scan results.
        if let idx = folders.firstIndex(where: { $0.id == folder.id }) {
            folders[idx].lastScanned = Date()
            folders[idx].lastAddedCount = added
            persist()
        }
        return added
    }

    /// Rescans every registered folder. Returns the total number of items added.
    @discardableResult
    func rescanAll(using env: AppEnvironment) async -> Int {
        var total = 0
        for folder in folders {
            total += await rescan(folder, using: env)
        }
        return total
    }

    /// Recursively collects video files under a path, honoring the depth limit.
    private func walk(path: String, depth: Int, env: AppEnvironment,
                      into videos: inout [RemoteFileItem]) async {
        guard depth <= maxDepth else { return }
        scanStatus = "Scanning \(path)…"
        let entries = (try? await env.smb.listDirectory(path: path)) ?? []
        for entry in entries {
            if entry.isDirectory {
                await walk(path: entry.path, depth: depth + 1, env: env, into: &videos)
            } else if VideoFileDetector.isVideoFile(entry.name) {
                videos.append(entry)
            }
        }
    }

    private func makeItem(for file: RemoteFileItem, env: AppEnvironment) async throws -> MediaItem {
        let url = try await env.smb.streamURL(for: file)
        let meta = MetadataParser.parse(filename: file.name, fileSize: file.size)
        return MediaItem(
            title: MetadataParser.cleanTitle(from: file.name),
            sourceType: .smb,
            playbackURL: url,
            legalAccessConfirmed: true, // the user owns their own network files
            metadata: meta
        )
    }
}
