//
//  RealDebridModels.swift
//  FrameTV
//
//  Codable types mirroring the Real-Debrid REST API (v1.0) responses
//  the app consumes. Fields the app doesn't use are intentionally omitted.
//

import Foundation

// MARK: - User

struct RealDebridUser: Codable, Hashable {
    let id: Int
    let username: String
    let email: String?
    let points: Int?
    let type: String          // "premium" or "free"
    let premium: Int?         // seconds of premium remaining
    let expiration: String?   // ISO8601 date string

    var isPremium: Bool { type.lowercased() == "premium" }

    /// Parsed expiration date, if present and well-formed.
    var expirationDate: Date? {
        guard let expiration else { return nil }
        let f = ISO8601DateFormatter()
        return f.date(from: expiration)
    }
}

// MARK: - Unrestrict

struct UnrestrictedLink: Codable, Hashable {
    let id: String?
    let filename: String?
    let filesize: Int64?
    let link: String?         // original
    let host: String?
    let download: String      // the resolved, playable URL
    let streamable: Int?

    var downloadURL: URL? { URL(string: download) }
    var isStreamable: Bool { (streamable ?? 0) == 1 }
}

// MARK: - Torrents

struct TorrentAddResponse: Codable, Hashable {
    let id: String
    let uri: String?
}

struct TorrentInfo: Codable, Hashable {
    let id: String
    let filename: String?
    let hash: String?
    let bytes: Int64?
    let status: String        // magnet_conversion, waiting_files_selection, downloading, downloaded, error, etc.
    let progress: Double?
    let files: [TorrentFile]?
    let links: [String]?

    var isReady: Bool { status.lowercased() == "downloaded" }
    var needsFileSelection: Bool { status.lowercased() == "waiting_files_selection" }
}

struct TorrentFile: Codable, Hashable, Identifiable {
    let id: Int
    let path: String
    let bytes: Int64
    let selected: Int

    var isSelected: Bool { selected == 1 }

    /// Just the filename portion of the path.
    var filename: String {
        (path as NSString).lastPathComponent
    }

    /// True if this entry looks like a playable video.
    var isPlayableVideo: Bool { VideoFileDetector.isVideoFile(filename) }
}

// MARK: - Downloads

struct DebridDownload: Codable, Hashable, Identifiable {
    let id: String
    let filename: String?
    let filesize: Int64?
    let link: String?
    let host: String?
    let download: String      // resolved URL
    let generated: String?

    var downloadURL: URL? { URL(string: download) }
}

// MARK: - Streaming / media info

struct StreamingLinks: Codable, Hashable {
    // Real-Debrid returns a dictionary keyed by quality; we keep it loose.
    let apple: QualityLinks?
    let dash: QualityLinks?
    let liveMP4: QualityLinks?
    let h264WebM: QualityLinks?

    enum CodingKeys: String, CodingKey {
        case apple
        case dash
        case liveMP4
        case h264WebM
    }
}

struct QualityLinks: Codable, Hashable {
    // Quality label -> URL string
    let full: String?
}

struct MediaInfo: Codable, Hashable {
    let filename: String?
    let hoster: String?
    let link: String?
    let type: String?
    let season: String?
    let episode: String?
    let year: String?
    let duration: Double?

    var seasonInt: Int? { season.flatMap { Int($0) } }
    var episodeInt: Int? { episode.flatMap { Int($0) } }
    var yearInt: Int? { year.flatMap { Int($0) } }
}

// MARK: - OAuth device flow

struct RDDeviceCode: Codable {
    let deviceCode: String
    let userCode: String
    let interval: Int
    let expiresIn: Int
    let verificationURL: String

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case interval
        case expiresIn = "expires_in"
        case verificationURL = "verification_url"
    }
}

struct RDCredentials: Codable {
    let clientID: String
    let clientSecret: String

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case clientSecret = "client_secret"
    }
}

struct RDToken: Codable {
    let accessToken: String
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

extension CharacterSet {
    /// Characters allowed in a URL query value (excludes reserved delimiters).
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "+&=?")
        return set
    }()
}
