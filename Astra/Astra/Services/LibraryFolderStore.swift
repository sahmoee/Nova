//
//  LibraryFolderStore.swift
//  Astra
//

import Foundation

struct LibraryFolder: Identifiable, Codable, Hashable {
    var id: UUID
    var shareID: UUID
    var displayName: String
    var path: String
    var lastScanned: Date?
    var lastAddedCount: Int

    init(id: UUID = UUID(), shareID: UUID, displayName: String, path: String,
         lastScanned: Date? = nil, lastAddedCount: Int = 0) {
        self.id = id; self.shareID = shareID; self.displayName = displayName
        self.path = path; self.lastScanned = lastScanned; self.lastAddedCount = lastAddedCount
    }
}

@MainActor
final class LibraryFolderStore: ObservableObject {
    @Published private(set) var folders: [LibraryFolder] = []
    @Published var scanningFolderID: UUID?
    @Published var scanStatus: String?

    private let defaultsKey = "library.folders.v1"
    private let defaults = UserDefaults.standard
    private let maxDepth = 4

    init() { load() }

    private func load() {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([LibraryFolder].self, from: data) else { return }
        folders = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(folders) { defaults.set(data, forKey: defaultsKey) }
    }

    func addFolder(shareID: UUID, displayName: String, path: String) -> LibraryFolder {
        let normalized = path.hasPrefix("/") || path.isEmpty ? path : "/" + path
        let folder = LibraryFolder(shareID: shareID, displayName: displayName, path: normalized)
        folders.append(folder); persist(); return folder
    }

    func removeFolder(_ folder: LibraryFolder) {
        folders.removeAll { $0.id == folder.id }; persist()
    }

    func loadShares() -> [SMBShare] {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let url = support?.appendingPathComponent("smb_shares.json"),
              let data = try? Data(contentsOf: url),
              let shares = try? JSONDecoder().decode([SMBShare].self, from: data) else { return [] }
        return shares
    }

    var availableShares: [SMBShare] { loadShares() }

    @discardableResult
    func rescan(_ folder: LibraryFolder, using env: AppEnvironment) async -> Int {
        guard let share = loadShares().first(where: { $0.id == folder.shareID }) else {
            scanStatus = "This folder's share is no longer configured."; return 0
        }
        scanningFolderID = folder.id
        scanStatus = "Connecting…"
        defer { scanningFolderID = nil; scanStatus = nil }
        do { try await env.smb.connect(to: share) }
        catch { scanStatus = "Couldn't connect to \(share.displayName)."; return 0 }

        var videos: [RemoteFileItem] = []
        await walk(path: folder.path.isEmpty ? "/" : folder.path, depth: 0, env: env, into: &videos)

        var added = 0
        for (index, file) in videos.enumerated() {
            scanStatus = "Adding \(index + 1) of \(videos.count)…"
            if let item = try? await makeItem(for: file, env: env) {
                let key = item.contentKey
                if !env.library.items.contains(where: { $0.contentKey == key }) {
                    env.library.add(item); added += 1
                }
            }
        }
        if let idx = folders.firstIndex(where: { $0.id == folder.id }) {
            folders[idx].lastScanned = Date(); folders[idx].lastAddedCount = added; persist()
        }
        return added
    }

    @discardableResult
    func rescanAll(using env: AppEnvironment) async -> Int {
        var total = 0
        for folder in folders { total += await rescan(folder, using: env) }
        return total
    }

    private func walk(path: String, depth: Int, env: AppEnvironment, into videos: inout [RemoteFileItem]) async {
        guard depth <= maxDepth else { return }
        scanStatus = "Scanning \(path)…"
        let entries = (try? await env.smb.listDirectory(path)) ?? []
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
        return MediaItem(title: MetadataParser.cleanTitle(from: file.name), sourceType: .smb,
                         playbackURL: url, legalAccessConfirmed: true, metadata: meta)
    }
}
