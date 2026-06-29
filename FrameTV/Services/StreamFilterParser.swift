//
//  StreamFilterParser.swift
//  FrameTV
//
//  Translates a natural-language filter phrase (e.g. "only cached 1080p under 8GB
//  with english audio") into concrete filter values. This runs entirely on-device
//  for the common cases, so it works without any AI/Worker call. The same output
//  shape can later be produced by the AI Worker for phrases this parser can't handle.
//

import Foundation

/// The filter values a phrase resolves to. All optional; nil means "no constraint".
struct ParsedStreamFilter: Equatable {
    var minQuality: StreamQuality? = nil
    var maxSizeGB: Double? = nil
    var cachedOnly: Bool = false
    var language: String? = nil          // uppercase tag, e.g. "EN"
    var codecPreferred: Bool = false     // user asked for efficient codec (HEVC/AV1)
    var hdrOnly: Bool = false

    var isEmpty: Bool {
        minQuality == nil && maxSizeGB == nil && !cachedOnly
            && language == nil && !codecPreferred && !hdrOnly
    }
}

enum StreamFilterParser {

    /// Parses a phrase into filter values using simple keyword/number matching.
    /// Recognizes: quality (4k/2160p, 1080p, 720p, 480p), "cached"/"instant",
    /// size ("under 8gb", "< 10 gb", "max 5gb"), languages (english/spanish/...),
    /// codec ("hevc"/"h265"/"av1"/"efficient"), and "hdr"/"dolby vision".
    static func parse(_ phrase: String) -> ParsedStreamFilter {
        let s = " " + phrase.lowercased() + " "
        var f = ParsedStreamFilter()

        // Quality.
        if s.contains("4k") || s.contains("2160") || s.contains("uhd") {
            f.minQuality = .uhd4k
        } else if s.contains("1080") || s.contains("fhd") || s.contains("full hd") {
            f.minQuality = .fhd1080
        } else if s.contains("720") || s.contains(" hd ") {
            f.minQuality = .hd720
        } else if s.contains("480") || s.contains(" sd ") {
            f.minQuality = .sd480
        }

        // Cached / instant.
        if s.contains("cached") || s.contains("instant") || s.contains("debrid") {
            f.cachedOnly = true
        }

        // Size: look for a number followed by gb/mb near "under/below/max/less".
        if let gb = parseSizeGB(from: s) { f.maxSizeGB = gb }

        // Language.
        let langs: [(String, String)] = [
            ("english", "EN"), ("eng", "EN"),
            ("spanish", "ES"), ("espanol", "ES"), ("latino", "ES"),
            ("french", "FR"), ("german", "DE"), ("italian", "IT"),
            ("japanese", "JA"), ("korean", "KO"), ("hindi", "HI"),
            ("portuguese", "PT"), ("russian", "RU")
        ]
        for (k, v) in langs where s.contains(k) { f.language = v; break }

        // Codec.
        if s.contains("hevc") || s.contains("h265") || s.contains("h.265")
            || s.contains("av1") || s.contains("efficient") || s.contains("x265") {
            f.codecPreferred = true
        }

        // HDR.
        if s.contains("hdr") || s.contains("dolby vision") || s.contains("dovi") {
            f.hdrOnly = true
        }

        return f
    }

    /// Extracts a size cap in GB from phrases like "under 8gb", "< 10 gb",
    /// "max 5 gb", "smaller than 12gb". MB values are converted to GB.
    private static func parseSizeGB(from s: String) -> Double? {
        // Match a number immediately followed (optionally with space) by gb or mb.
        // We scan tokens for the pattern.
        let scanner = s.replacingOccurrences(of: "<", with: " under ")
        let words = scanner.split(whereSeparator: { !$0.isNumber && $0 != "." && $0 != "g" && $0 != "m" && $0 != "b" })
        for w in words {
            let t = String(w)
            if t.hasSuffix("gb"), let n = Double(t.dropLast(2)) { return n }
            if t.hasSuffix("mb"), let n = Double(t.dropLast(2)) { return n / 1024.0 }
        }
        // Also handle "8 gb" with a space: find a number token that is followed by gb/mb.
        let parts = s.split(separator: " ").map(String.init)
        for i in 0..<parts.count {
            if let n = Double(parts[i]), i + 1 < parts.count {
                let unit = parts[i + 1]
                if unit.hasPrefix("gb") { return n }
                if unit.hasPrefix("mb") { return n / 1024.0 }
            }
        }
        return nil
    }
}
