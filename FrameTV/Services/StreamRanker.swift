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
            isCached: cached
        )
    }

    // MARK: - Ranking

    /// Sorts streams best-first. Order of preference:
    ///   1. Instantly playable / cached
    ///   2. Higher resolution
    ///   3. More seeders (for torrents)
    ///   4. Larger size (proxy for bitrate) but capped so absurd files don't win
    static func rank(_ streams: [StreamOption], preferredQuality: StreamQuality? = nil) -> [StreamOption] {
        streams.sorted { a, b in
            // Preferred quality bubbles to the top if specified and present.
            if let preferredQuality {
                let aPref = a.quality == preferredQuality
                let bPref = b.quality == preferredQuality
                if aPref != bPref { return aPref }
            }
            if a.isCached != b.isCached { return a.isCached }
            if a.quality.rank != b.quality.rank { return a.quality.rank > b.quality.rank }
            let aSeed = a.seeders ?? 0, bSeed = b.seeders ?? 0
            if aSeed != bSeed { return aSeed > bSeed }
            let aSize = a.sizeBytes ?? 0, bSize = b.sizeBytes ?? 0
            return aSize > bSize
        }
    }

    /// Picks the single best stream for auto-select, optionally honoring a quality
    /// preference and whether instant playback is required.
    static func autoSelect(_ streams: [StreamOption],
                           preferredQuality: StreamQuality?,
                           requireCached: Bool) -> StreamOption? {
        var pool = streams
        if requireCached { pool = pool.filter { $0.isCached } }
        return rank(pool, preferredQuality: preferredQuality).first
            ?? rank(streams, preferredQuality: preferredQuality).first
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
}
