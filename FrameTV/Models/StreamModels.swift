//
//  StreamModels.swift
//  FrameTV
//
//  Models for streams and subtitles returned by Stremio-protocol addons
//  (Stremio community addons, AIOStreams, Comet) and subtitle providers.
//

import Foundation

// MARK: - Stream source

/// A single playable stream option for a piece of content, as surfaced by an
/// addon. FrameTV presents a ranked list and the user (or auto-select) picks one.
struct StreamOption: Identifiable, Codable, Hashable {
    var id: String { "\(addonName)|\(rawTitle)|\(url?.absoluteString ?? infoHash ?? UUID().uuidString)" }

    var addonName: String          // which addon produced this (display/grouping)
    var name: String?              // short label the addon gives (e.g. provider)
    var rawTitle: String           // full descriptive title (filename, tags)
    var url: URL?                  // direct/HLS URL when the addon resolves one
    var infoHash: String?          // torrent infohash when the addon returns a magnet
    var fileIndex: Int?            // file index within a multi-file torrent
    var behaviorHints: StreamBehaviorHints?

    // Parsed quality signals (filled by StreamRanker).
    var quality: StreamQuality
    var sizeBytes: Int64?
    var seeders: Int?
    var isCached: Bool             // true if resolvable instantly (debrid-cached / direct)

    init(
        addonName: String,
        name: String? = nil,
        rawTitle: String,
        url: URL? = nil,
        infoHash: String? = nil,
        fileIndex: Int? = nil,
        behaviorHints: StreamBehaviorHints? = nil,
        quality: StreamQuality = .unknown,
        sizeBytes: Int64? = nil,
        seeders: Int? = nil,
        isCached: Bool = false
    ) {
        self.addonName = addonName
        self.name = name
        self.rawTitle = rawTitle
        self.url = url
        self.infoHash = infoHash
        self.fileIndex = fileIndex
        self.behaviorHints = behaviorHints
        self.quality = quality
        self.sizeBytes = sizeBytes
        self.seeders = seeders
        self.isCached = isCached
    }

    /// True if this stream can be played without first resolving a magnet through
    /// a debrid service (i.e. it already has a direct URL).
    var isDirectlyPlayable: Bool { url != nil }

    var sizeDisplay: String? {
        guard let sizeBytes else { return nil }
        return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

struct StreamBehaviorHints: Codable, Hashable {
    var bingeGroup: String?        // addons use this to group "play next" sources
    var notWebReady: Bool?
    var filename: String?
}

// MARK: - Quality

enum StreamQuality: String, Codable, CaseIterable, Hashable {
    case uhd4k = "4K"
    case fhd1080 = "1080p"
    case hd720 = "720p"
    case sd480 = "480p"
    case cam = "CAM"
    case unknown = "—"

    /// Higher is better; used for ranking.
    var rank: Int {
        switch self {
        case .uhd4k:   return 5
        case .fhd1080: return 4
        case .hd720:   return 3
        case .sd480:   return 2
        case .cam:     return 1
        case .unknown: return 0
        }
    }
}

// MARK: - Subtitles

struct SubtitleTrack: Identifiable, Codable, Hashable {
    var id: String
    var language: String           // ISO code or display name from provider
    var languageDisplay: String
    var url: URL?                  // remote subtitle file (srt/vtt)
    var isEmbedded: Bool           // true for tracks already inside the media
    var source: String             // provider/addon name

    init(
        id: String = UUID().uuidString,
        language: String,
        languageDisplay: String,
        url: URL? = nil,
        isEmbedded: Bool = false,
        source: String
    ) {
        self.id = id
        self.language = language
        self.languageDisplay = languageDisplay
        self.url = url
        self.isEmbedded = isEmbedded
        self.source = source
    }
}

// MARK: - Skip segments (intro / outro / recap)

enum SkipKind: String, Codable, Hashable {
    case intro
    case outro
    case recap

    var label: String {
        switch self {
        case .intro: return "Skip Intro"
        case .outro: return "Skip Outro"
        case .recap: return "Skip Recap"
        }
    }
}

struct SkipSegment: Identifiable, Codable, Hashable {
    var id: String { "\(kind.rawValue):\(Int(start))" }
    var kind: SkipKind
    var start: TimeInterval
    var end: TimeInterval

    func contains(_ t: TimeInterval) -> Bool { t >= start && t < end }
}
