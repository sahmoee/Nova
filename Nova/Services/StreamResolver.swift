//
//  StreamResolver.swift
//  Nova
//
//  Turns a selected StreamOption into a directly playable URL.
//
//  - If the stream already has a direct URL, it's returned as-is.
//  - If the stream is a torrent (infoHash only), it's resolved through the user's
//    own Real-Debrid account: build a magnet, add it, select the right file,
//    wait until ready, and unrestrict the link.
//
//  Resolution always goes through the user's configured debrid account; Nova does
//  not download or seed torrents itself.
//

import Foundation

enum StreamResolveError: LocalizedError {
    case noPlayableURL
    case unsupportedStream
    case debridUnavailable
    case fileNotFound
    case expiredLink
    case notCached(progress: Double?)
    case torrentFailed(status: String)
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .noPlayableURL:    return "This stream couldn't be turned into a playable link."
        case .unsupportedStream:return "This source doesn't offer a playable link or torrent. Choose another source."
        case .debridUnavailable:return "Resolving this stream needs a connected Real-Debrid account (Settings ▸ Real-Debrid)."
        case .fileNotFound:     return "The selected file wasn't found in the torrent."
        case .expiredLink:      return "This playback link has expired."
        case .notCached(let progress):
            let detail = progress.map { " (\(Int(($0).rounded()))% downloaded)" } ?? ""
            return "This torrent isn't cached on Real-Debrid yet\(detail). Choose a cached source, or try again once it finishes."
        case .torrentFailed(let status):
            return "Real-Debrid couldn't use this torrent (\(status.replacingOccurrences(of: "_", with: " "))). Choose another source."
        case .underlying(let e):return e.localizedDescription
        }
    }

    /// Whether this failure says something more useful than the generic message,
    /// so a picker that tried several sources can show the most helpful one.
    var isSpecific: Bool {
        switch self {
        case .noPlayableURL, .unsupportedStream: return false
        default: return true
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

        // Needs torrent resolution via debrid. A source with neither a link nor a
        // torrent (e.g. an addon's "configure me" entry) can never play.
        guard let infoHash = stream.infoHash else { throw StreamResolveError.unsupportedStream }
        guard hasDebridToken else { throw StreamResolveError.debridUnavailable }

        // The info hash comes from an untrusted addon; refuse anything that isn't
        // a well-formed BitTorrent info hash rather than building a malformed magnet.
        guard let magnet = Self.magnet(fromHash: infoHash, name: stream.behaviorHints?.filename ?? stream.rawTitle) else {
            throw StreamResolveError.unsupportedStream
        }

        // 1. Add the magnet to the user's Real-Debrid account.
        let added: TorrentAddResponse
        do { added = try await realDebrid.addMagnet(magnet) }
        catch { throw StreamResolveError.underlying(error) }

        do {
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
        } catch {
            // Every attempt adds a torrent to the user's account; don't leave failed
            // or still-downloading ones behind. Best effort, off the failure path.
            let client = realDebrid, id = added.id
            Task.detached { try? await client.deleteTorrent(id: id) }
            if let e = error as? StreamResolveError { throw e }
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
            // A dead or rejected magnet never recovers; fail now instead of polling for a minute.
            if info.hasFailed { throw StreamResolveError.torrentFailed(status: info.status) }
            if let files = info.files, !files.isEmpty { return info }
            if info.needsFileSelection { return info }
            try await Task.sleep(for: .seconds(2))
        }
        throw StreamResolveError.fileNotFound
    }

    /// Cached torrents turn "downloaded" within a few seconds of file selection.
    /// Anything still queued or downloading after this window isn't cached, and
    /// waiting the old three minutes only delayed the picker's fail-over.
    static let readyWindow: Duration = .seconds(24)

    private func waitUntilReady(id: String) async throws -> TorrentInfo {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.readyWindow)
        var last: TorrentInfo?
        while clock.now < deadline {
            let info = try await realDebrid.torrentInfo(id: id)
            if info.isReady, let links = info.links, !links.isEmpty { return info }
            if info.hasFailed { throw StreamResolveError.torrentFailed(status: info.status) }
            last = info
            try await Task.sleep(for: .seconds(2))
        }
        throw StreamResolveError.notCached(progress: last?.progress)
    }

    private static let hexDigits = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
    private static let base32Digits = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz234567")
    /// Query-value-safe characters: `.urlQueryAllowed` minus the separators that
    /// would let a display name inject extra magnet parameters.
    private static let magnetValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=+#?")
        return set
    }()

    /// Whether `hash` is a BitTorrent v1 info hash: 40 hex characters, or the
    /// 32-character base32 form.
    static func isValidInfoHash(_ hash: String) -> Bool {
        let scalars = hash.unicodeScalars
        switch scalars.count {
        case 40: return scalars.allSatisfy { hexDigits.contains($0) }
        case 32: return scalars.allSatisfy { base32Digits.contains($0) }
        default: return false
        }
    }

    /// Builds a magnet URI for an addon-supplied info hash. Returns nil when the
    /// hash is not a valid info hash (e.g. contains `&` or other injected params).
    static func magnet(fromHash rawHash: String, name: String?) -> String? {
        let hash = rawHash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidInfoHash(hash) else { return nil }
        var s = "magnet:?xt=urn:btih:\(hash)"
        if let name, let encoded = name.addingPercentEncoding(withAllowedCharacters: magnetValueAllowed) {
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
