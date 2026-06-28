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

    // Rich media signals parsed from the title (for badges + smart ranking).
    var hdr: HDRFormat = .none
    var videoCodec: VideoCodec = .unknown
    var audioFormat: AudioFormat = .unknown
    var audioChannels: String?     // e.g. "5.1", "7.1", "Atmos"
    var languages: [String] = []   // detected audio language tags, e.g. ["EN", "ES"]
    var sourceKind: SourceKind = .unknown   // where the stream comes from

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
        isCached: Bool = false,
        hdr: HDRFormat = .none,
        videoCodec: VideoCodec = .unknown,
        audioFormat: AudioFormat = .unknown,
        audioChannels: String? = nil,
        languages: [String] = [],
        sourceKind: SourceKind = .unknown
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
        self.hdr = hdr
        self.videoCodec = videoCodec
        self.audioFormat = audioFormat
        self.audioChannels = audioChannels
        self.languages = languages
        self.sourceKind = sourceKind
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

// MARK: - Rich media signals

enum HDRFormat: String, Codable, Hashable {
    case dolbyVision = "Dolby Vision"
    case hdr10Plus = "HDR10+"
    case hdr10 = "HDR10"
    case hdr = "HDR"
    case none = ""

    var rank: Int {
        switch self {
        case .dolbyVision: return 4
        case .hdr10Plus:   return 3
        case .hdr10:       return 2
        case .hdr:         return 1
        case .none:        return 0
        }
    }
}

enum VideoCodec: String, Codable, Hashable {
    case av1 = "AV1"
    case hevc = "HEVC"          // h.265 / x265
    case avc = "H.264"          // h.264 / x264
    case unknown = ""

    /// Preference: HEVC/AV1 are more efficient (smaller for same quality).
    var rank: Int {
        switch self {
        case .av1:     return 3
        case .hevc:    return 3
        case .avc:     return 1
        case .unknown: return 0
        }
    }
}

enum AudioFormat: String, Codable, Hashable {
    case atmos = "Atmos"
    case trueHD = "TrueHD"
    case dtsHD = "DTS-HD"
    case dts = "DTS"
    case eac3 = "EAC3"          // Dolby Digital Plus
    case ac3 = "AC3"            // Dolby Digital
    case aac = "AAC"
    case unknown = ""

    var rank: Int {
        switch self {
        case .atmos:   return 6
        case .trueHD:  return 5
        case .dtsHD:   return 4
        case .dts:     return 3
        case .eac3:    return 2
        case .ac3:     return 1
        case .aac:     return 1
        case .unknown: return 0
        }
    }
}

/// Where a stream physically comes from — drives the source-kind badge.
enum SourceKind: String, Codable, Hashable {
    case localSMB = "Local SMB"
    case cloud = "Cloud"           // debrid / direct cloud URL
    case torrent = "Torrent"
    case directURL = "Direct"
    case liveTV = "Live"
    case unknown = ""
}

// MARK: - Source health badges

/// A small descriptive badge shown on a stream row.
struct SourceBadge: Identifiable, Hashable {
    enum Tone: Hashable { case good, info, warn, premium }
    var id: String { label }
    var label: String
    var systemImage: String
    var tone: Tone
}

extension StreamOption {
    /// The set of health/quality badges to display for this stream, ordered by
    /// importance: availability, then video tier, then audio, then source/risk.
    var badges: [SourceBadge] {
        var out: [SourceBadge] = []

        if isCached {
            out.append(.init(label: "Cached", systemImage: "bolt.fill", tone: .good))
        }
        // "Fast" — cached or very high seed count means quick to start.
        if isCached || (seeders ?? 0) >= 50 {
            out.append(.init(label: "Fast", systemImage: "hare.fill", tone: .good))
        }
        if quality == .uhd4k {
            out.append(.init(label: "4K", systemImage: "4k.tv", tone: .premium))
        }
        switch hdr {
        case .dolbyVision:
            out.append(.init(label: "Dolby Vision", systemImage: "sparkles.tv", tone: .premium))
        case .hdr10Plus, .hdr10, .hdr:
            out.append(.init(label: hdr.rawValue, systemImage: "sparkles", tone: .premium))
        case .none:
            break
        }
        if audioFormat == .atmos {
            out.append(.init(label: "Dolby Atmos", systemImage: "hifispeaker.fill", tone: .premium))
        }
        // Low-seed risk for non-cached torrents with few seeders.
        if !isCached, let s = seeders, s > 0, s < 5 {
            out.append(.init(label: "Low Seed Risk", systemImage: "exclamationmark.triangle.fill", tone: .warn))
        }
        switch sourceKind {
        case .localSMB:
            out.append(.init(label: "Local SMB", systemImage: "externaldrive.connected.to.line.below", tone: .info))
        case .cloud:
            out.append(.init(label: "Cloud", systemImage: "cloud.fill", tone: .info))
        default:
            break
        }
        return out
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
