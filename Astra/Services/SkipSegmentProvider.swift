//
//  SkipSegmentProvider.swift
//  Astra
//
//  Supplies intro/outro/recap skip segments for the player. Two strategies:
//    1. Episode runtime heuristics (sensible defaults that work everywhere).
//    2. Hook points for a community segment API (e.g. an AniSkip-style service)
//       that can be wired in later without touching the player.
//
//  The heuristic is deliberately conservative: it only offers a "Skip Intro"
//  button during a likely intro window rather than auto-cutting blindly.
//

import Foundation

actor SkipSegmentProvider {

    /// Returns skip segments for an item. For now this uses runtime heuristics;
    /// when an external segment source is configured it can be merged in here.
    func segments(for item: MediaItem, duration: TimeInterval?) async -> [SkipSegment] {
        var result: [SkipSegment] = []

        // Only offer intro skipping for episodic content, where intros are common.
        guard item.isEpisode else { return result }

        // Intro heuristic: a ~75s window starting shortly after the open. Many
        // shows place the title sequence in the first couple of minutes.
        let introStart: TimeInterval = 8
        let introEnd: TimeInterval = introStart + 75
        result.append(SkipSegment(kind: .intro, start: introStart, end: introEnd))

        // Outro/credits heuristic: last ~45s when we know the duration.
        if let duration, duration > 120 {
            let outroStart = max(duration - 45, duration * 0.95)
            result.append(SkipSegment(kind: .outro, start: outroStart, end: duration))
        }

        return result
    }

    //
    // Hook for a real segment source. Implement this to query a community API by
    // IMDB id / episode and convert the response into SkipSegment values, then
    // merge with (or replace) the heuristic above.
    //
    // func externalSegments(imdbID: String, episode: EpisodeRef?) async -> [SkipSegment] { [] }
    //
}
