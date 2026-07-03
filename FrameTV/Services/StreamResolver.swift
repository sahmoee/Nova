//
//  StreamResolver.swift
//  FrameTV
//
//  Turns a selected StreamOption into a directly playable URL.
//
//  - If the stream already has a direct URL, it's returned as-is.
//  - If the stream is a torrent (infoHash only), it's resolved through the user's
//    own Real-Debrid account: build a magnet, add it, select the right file,
//    wait until ready, and unrestrict the link.
//
//  Resolution always goes through the user's configured debrid account; FrameTV does
//  not download or seed torrents itself.
//

import Foundation

enum StreamResolveError: LocalizedError {
    case noPlayableURL
    case debridUnavailable
    case fileNotFound
    case expiredLink
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .noPlayableURL:    return "This stream couldn't be turned into a playable link."
        case .debridUnavailable:return "Resolving this stream needs a connected Real-Debrid account (Settings ▸ Real-Debrid)."
        case .fileNotFound:     return "The selected file wasn't found in the torrent."
        case .expiredLink:      return "This playback link has expired. Trying the next stream."
        case .underlying(let e):return e.localizedDescription
        }
    }
}

actor StreamResolver {

    private let realDebrid: RealDebridClient

    init(realDebrid: RealDebridClient) {
        self.realDebrid = realDebrid
    }

    /// Resolves a StreamOption to a playable URL. `hasDebridToken` lets the caller
    /// short-circuit with a clear error when no account is connected.
    func resolve(_ stream: StreamOption, hasDebridToken: Bool) async throws -> URL {
        // Already playable.
        if let url = stream.url { return url }

        // Needs torrent resolution via debrid.
        guard let infoHash = stream.infoHash else { throw StreamResolveError.noPlayableURL }
        guard hasDebridToken else { throw StreamResolveError.debridUnavailable }

        let magnet = Self.magnet(fromHash: infoHash, name: stream.behaviorHints?.filename ?? stream.rawTitle)

        do {
            // 1. Add the magnet to the user's Real-Debrid account.
            let added = try await realDebrid.addMagnet(magnet)

            // 2. Wait for file metadata, then select the desired file.
            let info = try await waitForFiles(id: added.id)
            let fileID = chooseFileID(in: info, preferredIndex: stream.fileIndex)
            if let fileID {
                try await realDebrid.selectFiles(torrentID: added.id, fileIDs: [String(fileID)])
            } else {
                try await realDebrid.selectFiles(torrentID: added.id, fileIDs: [])  // all
            }

            // 3. Wait until downloaded and links are present.
            let ready = try await waitUntilReady(id: added.id)
            guard let link = ready.links?.first else { throw StreamResolveError.noPlayableURL }

            // 4. Unrestrict to a final playable URL.
            let unrestricted = try await realDebrid.unrestrictLink(link)
            guard let url = unrestricted.downloadURL else { throw StreamResolveError.noPlayableURL }
            return url
        } catch let e as StreamResolveError {
            throw e
        } catch {
            throw StreamResolveError.underlying(error)
        }
    }

    // MARK: - Helpers

    private func chooseFileID(in info: TorrentInfo, preferredIndex: Int?) -> Int? {
        let files = info.files ?? []
        // Stremio's fileIdx is 0-based into the torrent's file list.
        if let preferredIndex, preferredIndex >= 0, preferredIndex < files.count {
            return files[preferredIndex].id
        }
        // Otherwise pick the largest playable video.
        let videos = files.filter { $0.isPlayableVideo }
        return videos.max(by: { $0.bytes < $1.bytes })?.id
    }

    private func waitForFiles(id: String) async throws -> TorrentInfo {
        for _ in 0..<30 {
            let info = try await realDebrid.torrentInfo(id: id)
            if let files = info.files, !files.isEmpty { return info }
            if info.needsFileSelection { return info }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        throw StreamResolveError.fileNotFound
    }

    private func waitUntilReady(id: String) async throws -> TorrentInfo {
        for _ in 0..<60 {
            let info = try await realDebrid.torrentInfo(id: id)
            if info.isReady, let links = info.links, !links.isEmpty { return info }
            try await Task.sleep(nanoseconds: 3_000_000_000)
        }
        throw StreamResolveError.noPlayableURL
    }

    static func magnet(fromHash hash: String, name: String?) -> String {
        var s = "magnet:?xt=urn:btih:\(hash)"
        if let name, let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            s += "&dn=\(encoded)"
        }
        // A few well-known public trackers to help RD pick it up quickly.
        let trackers = [
            "udp://tracker.opentrackr.org:1337/announce",
            "udp://open.demonii.com:1337/announce",
            "udp://tracker.openbittorrent.com:6969/announce"
        ]
        for t in trackers {
            if let enc = t.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                s += "&tr=\(enc)"
            }
        }
        return s
    }
}
