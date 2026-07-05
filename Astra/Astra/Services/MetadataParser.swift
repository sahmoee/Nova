//
//  MetadataParser.swift
//  Astra
//
//  Best-effort parsing of season/episode/year/resolution out of filenames so
//  the library can show richer subtitles. Purely heuristic; never networked.
//

import Foundation

enum MetadataParser {

    /// Parses common patterns from a filename into MediaMetadata.
    static func parse(filename: String, fileSize: Int64? = nil) -> MediaMetadata {
        var meta = MediaMetadata(filename: filename, fileSize: fileSize)

        let lower = filename.lowercased()

        // Season / Episode — matches S01E02, s1e2, 1x02 styles.
        if let se = matchSeasonEpisode(in: lower) {
            meta.season = se.season
            meta.episode = se.episode
        }

        // Year — a 4-digit number in 1900...2099, preferring one in parens/brackets.
        if let year = matchYear(in: filename) {
            meta.year = year
        }

        // Resolution — 2160p/4k, 1080p, 720p, 480p.
        if let res = matchResolution(in: lower) {
            meta.resolution = res
        }

        // Codec — a few common tags.
        if let codec = matchCodec(in: lower) {
            meta.codec = codec
        }

        return meta
    }

    // MARK: - Pattern helpers

    private static func matchSeasonEpisode(in s: String) -> (season: Int, episode: Int)? {
        // S01E02 / s1e2
        if let r = s.range(of: #"s(\d{1,2})e(\d{1,3})"#, options: .regularExpression) {
            let match = String(s[r])
            let nums = match.dropFirst() // drop 's'
                .split(whereSeparator: { $0 == "e" })
                .compactMap { Int($0.filter(\.isNumber)) }
            if nums.count == 2 { return (nums[0], nums[1]) }
        }
        // 1x02
        if let r = s.range(of: #"(\d{1,2})x(\d{1,3})"#, options: .regularExpression) {
            let match = String(s[r])
            let nums = match.split(separator: "x").compactMap { Int($0) }
            if nums.count == 2 { return (nums[0], nums[1]) }
        }
        return nil
    }

    private static func matchYear(in s: String) -> Int? {
        // Prefer a year wrapped in () or [].
        if let r = s.range(of: #"[\(\[](19|20)\d{2}[\)\]]"#, options: .regularExpression) {
            let digits = s[r].filter(\.isNumber)
            return Int(digits)
        }
        // Otherwise any plausible 4-digit year token.
        if let r = s.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) {
            return Int(s[r])
        }
        return nil
    }

    private static func matchResolution(in s: String) -> String? {
        if s.contains("2160p") || s.contains("4k") { return "2160p" }
        if s.contains("1440p") { return "1440p" }
        if s.contains("1080p") { return "1080p" }
        if s.contains("720p")  { return "720p" }
        if s.contains("480p")  { return "480p" }
        return nil
    }

    private static func matchCodec(in s: String) -> String? {
        if s.contains("hevc") || s.contains("h265") || s.contains("x265") { return "HEVC" }
        if s.contains("h264") || s.contains("x264") || s.contains("avc") { return "H.264" }
        if s.contains("av1") { return "AV1" }
        return nil
    }

    /// Produces a clean display title from a filename by stripping extension,
    /// separators, and common scene tags.
    static func cleanTitle(from filename: String) -> String {
        var name = (filename as NSString).deletingPathExtension
        name = name.replacingOccurrences(of: ".", with: " ")
        name = name.replacingOccurrences(of: "_", with: " ")
        // Cut at the first SxxExx / year token if present, keeping the show/movie name.
        if let r = name.range(of: #"[sS]\d{1,2}[eE]\d{1,3}"#, options: .regularExpression) {
            name = String(name[..<r.lowerBound])
        }
        return name.trimmingCharacters(in: .whitespaces)
    }
}
