//
//  StreamRanker.swift
//  FrameTV
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
}
