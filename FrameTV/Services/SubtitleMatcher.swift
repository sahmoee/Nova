//
//  SubtitleMatcher.swift
//  FrameTV
//
//  Picks the best subtitle track for an item based on the user's preferred subtitle
//  language, embedded-vs-external preference, and a light filename/season/episode
//  sanity check. Used to auto-select a track instead of making the user choose.
//

import Foundation

enum SubtitleMatcher {
    /// Returns the best track for the item given a preferred language code (e.g. "en"),
    /// or nil if there are no tracks. Ranking:
    ///   1) exact preferred-language match,
    ///   2) language family match (e.g. "en" vs "en-US"),
    ///   3) embedded tracks (already in sync) over external,
    ///   4) provider order as a tiebreak.
    static func best(for item: MediaItem, preferredLanguage: String) -> SubtitleTrack? {
        bestTrack(in: item.subtitles,
                  preferredLanguage: preferredLanguage,
                  filename: item.metadata.filename,
                  season: item.episode?.season,
                  episode: item.episode?.number)
    }

    static func bestTrack(in tracks: [SubtitleTrack],
                          preferredLanguage: String,
                          filename: String? = nil,
                          season: Int? = nil,
                          episode: Int? = nil) -> SubtitleTrack? {
        guard !tracks.isEmpty else { return nil }
        let pref = preferredLanguage.lowercased()
        let prefBase = String(pref.prefix(2))

        func score(_ t: SubtitleTrack) -> Int {
            var s = 0
            let lang = t.language.lowercased()
            let base = String(lang.prefix(2))
            if lang == pref { s += 100 }
            else if base == prefBase && !prefBase.isEmpty { s += 60 }
            if t.isEmbedded { s += 20 }
            // Light filename season/episode agreement bonus for external files.
            if let fn = filename?.lowercased(), let se = season, let ep = episode {
                let pattern = String(format: "s%02de%02d", se, ep)
                if fn.contains(pattern) { s += 5 }
            }
            return s
        }

        return tracks.max { score($0) < score($1) }
    }

    /// Whether a confident auto-pick exists (a preferred-language match), so callers
    /// can choose to auto-enable subtitles only when the match is good.
    static func hasConfidentMatch(for item: MediaItem, preferredLanguage: String) -> Bool {
        let prefBase = String(preferredLanguage.lowercased().prefix(2))
        guard !prefBase.isEmpty else { return false }
        return item.subtitles.contains { String($0.language.lowercased().prefix(2)) == prefBase }
    }
}
