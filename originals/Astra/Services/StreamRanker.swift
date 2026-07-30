//
//  StreamRanker.swift
//  Astra
//
//  Normalizes raw addon streams into StreamOption and ranks them. Addons encode
//  quality/size/seeders in free-form titles, so this parses common conventions.
//

import Foundation

enum StreamRanker {

    // MARK: - Normalization

    static func normalize(_ raw: AddonStream, addonName: String) -> StreamOption {
        let title = raw.title ?? raw.description ?? raw.name ?? "Stream"
        let haystack = [raw.name, raw.title, raw.description, raw.behaviorHints?.filename]
            .compactMap { $0 }
            .joined(separator: " ")

        let quality = parseQuality(from: haystack)
        let size = raw.behaviorHints?.videoSize ?? parseSize(from: haystack)
        let seeders = parseSeeders(from: haystack)

        let url = raw.url.flatMap { URL(string: $0) }
        let cached = isCached(from: haystack) || url != nil

        let hints = StreamBehaviorHints(
            bingeGroup: raw.behaviorHints?.bingeGroup,
            notWebReady: raw.behaviorHints?.notWebReady,
            filename: raw.behaviorHints?.filename
        )

        // Rich signals for badges + smart ranking.
        let hdr = parseHDR(from: haystack)
        let codec = parseCodec(from: haystack)
        let audio = parseAudio(from: haystack)
        let channels = parseChannels(from: haystack)
        let langs = parseLanguages(from: haystack)
        // Decide where the stream comes from: a direct URL with no infohash is a
        // cloud/debrid/direct source; an infohash is a torrent.
        let kind: SourceKind
        if raw.infoHash != nil { kind = .torrent }
        else if url != nil { kind = cached ? .cloud : .directURL }
        else { kind = .unknown }

        return StreamOption(
            addonName: addonName,
            name: raw.name,
            rawTitle: title,
            url: url,
            infoHash: raw.infoHash,
            fileIndex: raw.fileIdx,
            behaviorHints: hints,
            quality: quality,
            sizeBytes: size,
            seeders: seeders,
            isCached: cached,
            hdr: hdr,
            videoCodec: codec,
            audioFormat: audio,
            audioChannels: channels,
            languages: langs,
            sourceKind: kind
        )
    }

    // MARK: - Ranking

    /// A bundle of the user's streaming preferences from Settings, used to bias and
    /// filter the stream list. All fields are optional/zero-defaulted so existing
    /// callers can pass `.init()` for "no extra preference".
    struct StreamPreferences {
        var preferredQuality: StreamQuality? = nil
        var preferredLanguage: String? = nil
        var maxSizeGB: Int = 0                       // 0 = no limit
        var preferredSource: SourceKind? = nil        // nil = any
        var minSeeders: Int = 0                       // 0 = no minimum
        var preferEfficientCodec: Bool = false
        /// User-ordered fallback chain of source kinds; earlier kinds score higher.
        var sourcePriority: [SourceKind] = []
        /// Addon names in the user's Addons-screen order; earlier addons score
        /// higher, so reordering addons directly biases stream ranking.
        var addonPriority: [String] = []
    }

    /// Collapses streams that are the same underlying file offered by several
    /// addons (same infohash + file index, or same URL). Cached copies win;
    /// otherwise the first (highest-ranked source) is kept.
    static func dedupeByIdentity(_ streams: [StreamOption]) -> [StreamOption] {
        var best: [String: StreamOption] = [:]
        var order: [String] = []
        for s in streams {
            let key: String
            if let hash = s.infoHash {
                key = "\(hash.lowercased()):\(s.fileIndex ?? -1)"
            } else if let url = s.url {
                key = url.absoluteString
            } else {
                key = s.id
            }
            if let existing = best[key] {
                // Prefer the cached copy; otherwise keep the first seen.
                if s.isCached && !existing.isCached { best[key] = s }
            } else {
                best[key] = s
                order.append(key)
            }
        }
        return order.compactMap { best[$0] }
    }

    /// Sorts streams best-first using a weighted score across all signals:
    /// availability, resolution, HDR tier, codec efficiency, audio format, seeders,
    /// and a sane file-size sweet spot. The user's preferences bias the result.
    static func rank(_ streams: [StreamOption],
                     preferredQuality: StreamQuality? = nil,
                     preferredLanguage: String? = nil) -> [StreamOption] {
        rank(streams, preferences: StreamPreferences(preferredQuality: preferredQuality,
                                                     preferredLanguage: preferredLanguage))
    }

    /// Preference-aware ranking. Streams over the size cap or under the seeder floor
    /// are kept but pushed to the bottom (so the list is never empty), then the rest
    /// are ordered by weighted score.
    static func rank(_ streams: [StreamOption], preferences p: StreamPreferences) -> [StreamOption] {
        streams.sorted { a, b in
            let pa = passesHardPreferences(a, p)
            let pb = passesHardPreferences(b, p)
            if pa != pb { return pa }   // passing streams sort above failing ones
            let sa = score(a, preferences: p)
            let sb = score(b, preferences: p)
            if sa != sb { return sa > sb }
            return (a.sizeBytes ?? 0) > (b.sizeBytes ?? 0)
        }
    }

    /// Whether a stream satisfies the user's hard caps (size, min seeders). Cached
    /// sources are exempt from the seeder floor (they don't rely on seeders).
    private static func passesHardPreferences(_ s: StreamOption, _ p: StreamPreferences) -> Bool {
        if p.maxSizeGB > 0, let bytes = s.sizeBytes {
            let gb = Double(bytes) / 1_073_741_824.0
            if gb > Double(p.maxSizeGB) { return false }
        }
        if p.minSeeders > 0, !s.isCached, s.sourceKind == .torrent {
            if (s.seeders ?? 0) < p.minSeeders { return false }
        }
        return true
    }

    static func score(_ s: StreamOption,
                      preferredQuality: StreamQuality?,
                      preferredLanguage: String?) -> Int {
        score(s, preferences: StreamPreferences(preferredQuality: preferredQuality,
                                                preferredLanguage: preferredLanguage))
    }

    /// Computes a single comparable score for a stream. Weights are tuned so that
    /// instant availability and resolution dominate, with HDR/codec/audio refining
    /// between otherwise-similar options.
    static func score(_ s: StreamOption, preferences p: StreamPreferences) -> Int {
        var score = 0
        // User-ordered fallback chain: earlier source kinds get a graded bonus.
        if let idx = p.sourcePriority.firstIndex(of: s.sourceKind) {
            score += max(0, p.sourcePriority.count - idx) * 40
        }
        // Addon order bias: streams from addons the user ranked higher win ties.
        if let idx = p.addonPriority.firstIndex(of: s.addonName) {
            score += max(0, p.addonPriority.count - idx) * 12
        }
        // Availability is paramount: a cached/instant source beats a faster-on-paper
        // torrent the user has to wait for.
        if s.isCached { score += 1000 }
        // Honor an explicit quality preference strongly.
        if let pq = p.preferredQuality, s.quality == pq { score += 400 }
        // Preferred source kind.
        if let ps = p.preferredSource, s.sourceKind == ps { score += 200 }
        // Resolution.
        score += s.quality.rank * 100
        // HDR tier (Dolby Vision > HDR10+ > HDR10 > HDR).
        score += s.hdr.rank * 40
        // Audio format (Atmos/TrueHD/DTS-HD ... ).
        score += s.audioFormat.rank * 12
        // Codec efficiency (HEVC/AV1 preferred), boosted when the user opts in.
        score += s.videoCodec.rank * (p.preferEfficientCodec ? 30 : 10)
        // Seeders give confidence for non-cached torrents (diminishing).
        let seed = s.seeders ?? 0
        score += min(seed, 200) / 10
        // Preferred language match.
        if let pl = p.preferredLanguage?.uppercased(), !pl.isEmpty,
           s.languages.contains(where: { $0.uppercased() == pl }) {
            score += 60
        }
        // File-size sweet spot: reward a reasonable size, gently penalize absurdly
        // large files (likely remuxes that may stutter) and tiny ones (low bitrate).
        if let bytes = s.sizeBytes {
            let gb = Double(bytes) / 1_073_741_824.0
            switch s.quality {
            case .uhd4k:
                if gb >= 8 && gb <= 60 { score += 30 } else if gb > 80 { score -= 30 }
            case .fhd1080:
                if gb >= 2 && gb <= 20 { score += 30 } else if gb > 30 { score -= 20 }
            default:
                if gb >= 0.5 && gb <= 8 { score += 20 }
            }
        }
        return score
    }

    /// Picks the single best stream for auto-select, optionally honoring a quality
    /// preference and whether instant playback is required.
    static func autoSelect(_ streams: [StreamOption],
                           preferredQuality: StreamQuality?,
                           requireCached: Bool,
                           preferredLanguage: String? = nil) -> StreamOption? {
        autoSelect(streams,
                   preferences: StreamPreferences(preferredQuality: preferredQuality,
                                                  preferredLanguage: preferredLanguage),
                   requireCached: requireCached)
    }

    /// Preference-aware auto-select. Applies the cached requirement, then ranks with
    /// the full preference set, falling back to the unfiltered best if nothing
    /// passes the hard caps.
    static func autoSelect(_ streams: [StreamOption],
                           preferences p: StreamPreferences,
                           requireCached: Bool) -> StreamOption? {
        var pool = streams
        if requireCached { pool = pool.filter { $0.isCached } }
        let ranked = rank(pool, preferences: p)
        // Prefer the best stream that passes the hard caps; otherwise best overall.
        return ranked.first(where: { passesHardPreferences($0, p) })
            ?? ranked.first
            ?? rank(streams, preferences: p).first
    }

    // MARK: - Parsing helpers

    static func parseQuality(from s: String) -> StreamQuality {
        let lower = s.lowercased()
        if lower.contains("2160") || lower.contains("4k") || lower.contains("uhd") { return .uhd4k }
        if lower.contains("1080") { return .fhd1080 }
        if lower.contains("720") { return .hd720 }
        if lower.contains("480") { return .sd480 }
        if lower.contains("cam") || lower.contains("ts ") || lower.contains("telesync") { return .cam }
        return .unknown
    }

    /// Parses sizes like "1.5 GB", "750 MB", "1,4 GiB".
    static func parseSize(from s: String) -> Int64? {
        let pattern = #"(\d+[.,]?\d*)\s*(GB|GiB|MB|MiB|TB|TiB)"#
        guard let r = s.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let match = String(s[r])
        let numStr = match.filter { $0.isNumber || $0 == "." || $0 == "," }
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(numStr) else { return nil }
        let unit = match.uppercased()
        let multiplier: Double
        if unit.contains("TB") || unit.contains("TIB") { multiplier = 1_099_511_627_776 }
        else if unit.contains("GB") || unit.contains("GIB") { multiplier = 1_073_741_824 }
        else { multiplier = 1_048_576 } // MB
        return Int64(value * multiplier)
    }

    /// Parses seeders like "👤 1234", "Seeders: 56", "S:56".
    static func parseSeeders(from s: String) -> Int? {
        let patterns = [#"👤\s*(\d+)"#, #"[Ss]eeders?:?\s*(\d+)"#, #"\bS:?\s*(\d+)"#]
        for p in patterns {
            if let r = s.range(of: p, options: .regularExpression) {
                let digits = s[r].filter(\.isNumber)
                if let n = Int(digits) { return n }
            }
        }
        return nil
    }

    static func isCached(from s: String) -> Bool {
        let lower = s.lowercased()
        // Common cached markers used by debrid-backed addons.
        return lower.contains("cached")
            || lower.contains("⚡")
            || lower.contains("[rd+]")
            || lower.contains("instant")
    }

    static func parseHDR(from s: String) -> HDRFormat {
        let l = s.lowercased()
        if l.contains("dolby vision") || l.contains("dovi") || l.contains("dv ") || l.contains(".dv.") || l.contains("[dv]") {
            return .dolbyVision
        }
        if l.contains("hdr10+") || l.contains("hdr10plus") || l.contains("hdr+ ") { return .hdr10Plus }
        if l.contains("hdr10") { return .hdr10 }
        if l.contains("hdr") { return .hdr }
        return .none
    }

    static func parseCodec(from s: String) -> VideoCodec {
        let l = s.lowercased()
        if l.contains("av1") { return .av1 }
        if l.contains("x265") || l.contains("h265") || l.contains("h.265") || l.contains("hevc") { return .hevc }
        if l.contains("x264") || l.contains("h264") || l.contains("h.264") || l.contains("avc") { return .avc }
        return .unknown
    }

    static func parseAudio(from s: String) -> AudioFormat {
        let l = s.lowercased()
        if l.contains("atmos") { return .atmos }
        if l.contains("truehd") || l.contains("true-hd") { return .trueHD }
        if l.contains("dts-hd") || l.contains("dts hd") || l.contains("dtshd") { return .dtsHD }
        if l.contains("dts") { return .dts }
        if l.contains("eac3") || l.contains("e-ac3") || l.contains("ddp") || l.contains("dd+") { return .eac3 }
        if l.contains("ac3") || l.contains("dolby digital") || l.contains(" dd ") { return .ac3 }
        if l.contains("aac") { return .aac }
        return .unknown
    }

    /// Parses surround channel layouts like "5.1", "7.1", or Atmos.
    static func parseChannels(from s: String) -> String? {
        if s.lowercased().contains("atmos") { return "Atmos" }
        if let r = s.range(of: #"\b[5-9]\.1\b|\b7\.1\b|\b2\.0\b"#, options: .regularExpression) {
            return String(s[r])
        }
        return nil
    }

    /// Detects common audio-language tags in a title. Returns uppercase ISO-ish codes.
    static func parseLanguages(from s: String) -> [String] {
        let map: [String: String] = [
            "english": "EN", "eng": "EN", " en ": "EN",
            "spanish": "ES", "espanol": "ES", "latino": "ES",
            "french": "FR", "francais": "FR",
            "german": "DE", "deutsch": "DE",
            "italian": "IT", "japanese": "JA", "korean": "KO",
            "hindi": "HI", "portuguese": "PT", "russian": "RU",
            "multi": "MULTI", "dual": "DUAL"
        ]
        let l = " " + s.lowercased() + " "
        var found: [String] = []
        for (k, v) in map where l.contains(k) {
            if !found.contains(v) { found.append(v) }
        }
        return found
    }

    // MARK: - Best-match labels

    /// A human-friendly superlative for a stream, shown as a badge in the picker so
    /// the user can choose by intent rather than reading raw titles.
    enum StreamLabel: String {
        case bestOverall   = "Best Overall"
        case fastestStart  = "Fastest Start"
        case smallestFile  = "Smallest File"
        case bestAudio     = "Best Audio"
        case bestHDR       = "Best HDR"
        case mostReliable  = "Most Reliable"
        case lowSeeders    = "Avoid — Low Seeders"

        /// SF Symbol for the badge.
        var systemImage: String {
            switch self {
            case .bestOverall:  return "star.fill"
            case .fastestStart: return "bolt.fill"
            case .smallestFile: return "arrow.down.circle.fill"
            case .bestAudio:    return "hifispeaker.fill"
            case .bestHDR:      return "sparkles.tv.fill"
            case .mostReliable: return "checkmark.seal.fill"
            case .lowSeeders:   return "exclamationmark.triangle.fill"
            }
        }

        /// Whether this is a warning (rendered in a cautionary color) vs. a positive.
        var isWarning: Bool { self == .lowSeeders }
    }

    /// Computes superlative labels for a set of streams, given the user's preferences.
    /// Each "best" label is awarded to at most one stream; the low-seeders warning can
    /// apply to several. Returns a map keyed by `StreamOption.id`. A stream may earn
    /// more than one label.
    static func labels(for streams: [StreamOption],
                       preferences p: StreamPreferences = .init()) -> [String: [StreamLabel]] {
        guard !streams.isEmpty else { return [:] }
        var out: [String: [StreamLabel]] = [:]
        func add(_ id: String, _ label: StreamLabel) {
            out[id, default: []].append(label)
        }

        // Best Overall: highest weighted score under the user's preferences.
        if let best = rank(streams, preferences: p).first {
            add(best.id, .bestOverall)
        }
        // Fastest Start: a cached/instant stream, highest quality among those.
        if let fastest = streams.filter({ $0.isCached })
            .max(by: { $0.quality.rank < $1.quality.rank }) {
            add(fastest.id, .fastestStart)
        }
        // Smallest File: smallest known size that is still at least 720p (avoid junk).
        if let smallest = streams
            .filter({ ($0.sizeBytes ?? 0) > 0 && $0.quality.rank >= StreamQuality.hd720.rank })
            .min(by: { ($0.sizeBytes ?? .max) < ($1.sizeBytes ?? .max) }) {
            add(smallest.id, .smallestFile)
        }
        // Best Audio: highest audio-format rank (Atmos/TrueHD/DTS-HD ...).
        if let bestAudio = streams.max(by: { $0.audioFormat.rank < $1.audioFormat.rank }),
           bestAudio.audioFormat.rank > 0 {
            add(bestAudio.id, .bestAudio)
        }
        // Best HDR: highest HDR tier (Dolby Vision > HDR10+ > HDR10 > HDR).
        if let bestHDR = streams.max(by: { $0.hdr.rank < $1.hdr.rank }),
           bestHDR.hdr.rank > 0 {
            add(bestHDR.id, .bestHDR)
        }
        // Most Reliable: cached, or the highest-seeded torrent.
        if let reliable = streams.max(by: { reliabilityScore($0) < reliabilityScore($1) }),
           reliabilityScore(reliable) > 0 {
            add(reliable.id, .mostReliable)
        }
        // Low-seeders warning: non-cached torrents with few seeders.
        for s in streams where !s.isCached && s.sourceKind == .torrent {
            if (s.seeders ?? 0) < 5 { add(s.id, .lowSeeders) }
        }
        return out
    }

    /// A reliability proxy: cached sources are most reliable, otherwise seeder count.
    private static func reliabilityScore(_ s: StreamOption) -> Int {
        if s.isCached { return 10_000 }
        return s.seeders ?? 0
    }

    /// A short, plain-language explanation of why a stream is a good pick, given the
    /// user's preferences. Used for the "Why this stream?" detail. Returns a list of
    /// positive reasons (e.g. "Cached / instant", "1080p", "Efficient codec").
    static func explain(_ s: StreamOption, preferences p: StreamPreferences = .init()) -> [String] {
        var reasons: [String] = []
        if s.isCached { reasons.append("Cached / instant start") }
        if s.quality != .unknown { reasons.append(s.quality.rawValue) }
        if s.hdr.rank > 0 { reasons.append(s.hdr.rawValue) }
        if s.audioFormat.rank > 0 { reasons.append(s.audioFormat.rawValue) }
        if s.videoCodec == .hevc || s.videoCodec == .av1 { reasons.append("Efficient codec (\(s.videoCodec.rawValue))") }
        if let ps = p.preferredSource, s.sourceKind == ps { reasons.append("Preferred source") }
        if let pl = p.preferredLanguage?.uppercased(), !pl.isEmpty,
           s.languages.contains(where: { $0.uppercased() == pl }) {
            reasons.append("\(pl) audio")
        }
        if !s.isCached, s.sourceKind == .torrent, let seeders = s.seeders, seeders >= 10 {
            reasons.append("\(seeders) seeders")
        }
        if let bytes = s.sizeBytes {
            let gb = Double(bytes) / 1_073_741_824.0
            // Mention a sensible size for the quality.
            switch s.quality {
            case .uhd4k where gb >= 8 && gb <= 60: reasons.append("Good 4K size")
            case .fhd1080 where gb >= 2 && gb <= 20: reasons.append("Good 1080p size")
            default: break
            }
        }
        if reasons.isEmpty { reasons.append("Available stream") }
        return reasons
    }

    /// A plain-language confidence level for how smoothly a stream is likely to play,
    /// so users get an instant read without parsing technical badges.
    enum PlaybackConfidence: String {
        case readyToPlay      = "Ready to Play"
        case likelyCompatible = "Likely Compatible"
        case mayNeedVLC       = "May Need VLC"
        case slowSource       = "Slow Source"
        case lowConfidence    = "Low Confidence"

        /// SF Symbol used alongside the label.
        var systemImage: String {
            switch self {
            case .readyToPlay:      return "checkmark.seal.fill"
            case .likelyCompatible: return "checkmark.circle"
            case .mayNeedVLC:       return "wand.and.stars"
            case .slowSource:       return "tortoise.fill"
            case .lowConfidence:    return "questionmark.circle"
            }
        }
    }

    /// Classifies a stream into a single confidence level. Codecs/containers that
    /// AVPlayer handles natively rate higher; formats that typically need VLC (e.g.
    /// MKV containers, EAC3/DTS audio) are flagged as "May Need VLC". Uncached torrents
    /// with few seeders are flagged as slow.
    static func confidence(_ s: StreamOption) -> PlaybackConfidence {
        // Uncached torrent with low seeders: slow to start regardless of format.
        if !s.isCached, s.sourceKind == .torrent {
            if let seeders = s.seeders, seeders < 5 { return .slowSource }
        }
        let title = s.rawTitle.lowercased()
        // Formats AVPlayer often can't play but VLC can.
        let needsVLC = title.contains(".mkv") || title.contains("matroska")
            || s.audioFormat.rawValue.lowercased().contains("dts")
            || title.contains("dts") || title.contains("eac3") || title.contains("truehd")
        if needsVLC { return .mayNeedVLC }
        // Cached/direct with a known good quality: ready to play.
        if s.isCached || s.sourceKind == .cloud || s.sourceKind == .localSMB || s.sourceKind == .directURL {
            if s.quality != .unknown { return .readyToPlay }
            return .likelyCompatible
        }
        if s.quality != .unknown { return .likelyCompatible }
        return .lowConfidence
    }
}
