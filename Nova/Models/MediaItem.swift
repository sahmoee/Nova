//
//  MediaItem.swift
//  Nova
//
//  The core unit of the library. Everything playable becomes a MediaItem.
//

import Foundation

struct MediaItem: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var sourceType: SourceType
    var playbackURL: URL
    var posterURL: URL?
    var backdropURL: URL?
    var duration: TimeInterval?
    var lastPlayedPosition: TimeInterval
    var addedDate: Date
    var lastPlayedDate: Date?
    var isFavorite: Bool
    var legalAccessConfirmed: Bool
    var metadata: MediaMetadata

    // MARK: - Phase 3 content linkage (all optional for backward compatibility)

    /// Cross-service identity (IMDB/TMDB/Trakt) when this item is catalog content.
    var contentID: ContentID?
    /// For series episodes: which episode this MediaItem represents.
    var episode: EpisodeRef?
    /// The series title, when this item is an episode (for display + grouping).
    var seriesTitle: String?
    /// Subtitle tracks discovered for this item.
    var subtitles: [SubtitleTrack]
    /// Skip segments (intro/outro/recap) when known.
    var skipSegments: [SkipSegment]

    // MARK: - Library organization (all optional for backward compatibility)

    /// User-applied free-form tags for filtering/organization.
    var tags: [String]
    /// Hidden/archived from the main library view (kept, but out of sight).
    var isHidden: Bool
    /// Remembered subtitle timing offset in seconds for this title (+ = later).
    var subtitleOffset: Double

    /// A stable identity for the *same content*, independent of the random `id`
    /// assigned per playback. Used to dedupe the library so replaying an episode
    /// doesn't create a second entry. Prefers cross-service IDs, then series +
    /// episode, then the playback URL, then the title.
    var contentKey: String {
        if let contentID {
            let raw = contentID.stableKey
            // Only trust a real cross-service ID, not the "unknown:" fallback.
            if !raw.hasPrefix("unknown:") {
                if let episode { return "\(raw)|s\(episode.season)e\(episode.number)" }
                return raw
            }
        }
        if let seriesTitle, let episode {
            return "series:\(seriesTitle.lowercased())|s\(episode.season)e\(episode.number)"
        }
        // Fall back to the playback URL (stable for a given file/stream), then title.
        let urlKey = playbackURL.absoluteString
        if !urlKey.isEmpty { return "url:\(urlKey)" }
        return "title:\(title.lowercased())"
    }

    init(
        id: UUID = UUID(),
        title: String,
        sourceType: SourceType,
        playbackURL: URL,
        posterURL: URL? = nil,
        backdropURL: URL? = nil,
        duration: TimeInterval? = nil,
        lastPlayedPosition: TimeInterval = 0,
        addedDate: Date = Date(),
        lastPlayedDate: Date? = nil,
        isFavorite: Bool = false,
        legalAccessConfirmed: Bool = false,
        metadata: MediaMetadata = MediaMetadata(),
        contentID: ContentID? = nil,
        episode: EpisodeRef? = nil,
        seriesTitle: String? = nil,
        subtitles: [SubtitleTrack] = [],
        skipSegments: [SkipSegment] = [],
        tags: [String] = [],
        isHidden: Bool = false,
        subtitleOffset: Double = 0
    ) {
        self.id = id
        self.title = title
        self.sourceType = sourceType
        self.playbackURL = playbackURL
        self.posterURL = posterURL
        self.backdropURL = backdropURL
        self.duration = duration
        self.lastPlayedPosition = lastPlayedPosition
        self.addedDate = addedDate
        self.lastPlayedDate = lastPlayedDate
        self.isFavorite = isFavorite
        self.legalAccessConfirmed = legalAccessConfirmed
        self.metadata = metadata
        self.contentID = contentID
        self.episode = episode
        self.seriesTitle = seriesTitle
        self.subtitles = subtitles
        self.skipSegments = skipSegments
        self.tags = tags
        self.isHidden = isHidden
        self.subtitleOffset = subtitleOffset
    }

    // Backward-compatible decoding: libraries saved before Phase 3 lack the new
    // keys, so they decode to nil/empty rather than failing.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        sourceType = try c.decode(SourceType.self, forKey: .sourceType)
        playbackURL = try c.decode(URL.self, forKey: .playbackURL)
        posterURL = try c.decodeIfPresent(URL.self, forKey: .posterURL)
        backdropURL = try c.decodeIfPresent(URL.self, forKey: .backdropURL)
        duration = try c.decodeIfPresent(TimeInterval.self, forKey: .duration)
        lastPlayedPosition = try c.decodeIfPresent(TimeInterval.self, forKey: .lastPlayedPosition) ?? 0
        addedDate = try c.decodeIfPresent(Date.self, forKey: .addedDate) ?? Date()
        lastPlayedDate = try c.decodeIfPresent(Date.self, forKey: .lastPlayedDate)
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        legalAccessConfirmed = try c.decodeIfPresent(Bool.self, forKey: .legalAccessConfirmed) ?? false
        metadata = try c.decodeIfPresent(MediaMetadata.self, forKey: .metadata) ?? MediaMetadata()
        contentID = try c.decodeIfPresent(ContentID.self, forKey: .contentID)
        episode = try c.decodeIfPresent(EpisodeRef.self, forKey: .episode)
        seriesTitle = try c.decodeIfPresent(String.self, forKey: .seriesTitle)
        subtitles = try c.decodeIfPresent([SubtitleTrack].self, forKey: .subtitles) ?? []
        skipSegments = try c.decodeIfPresent([SkipSegment].self, forKey: .skipSegments) ?? []
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        isHidden = try c.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        subtitleOffset = try c.decodeIfPresent(Double.self, forKey: .subtitleOffset) ?? 0
    }

    // MARK: - Derived helpers

    /// Fraction watched, 0...1, based on saved position and known duration.
    var progressFraction: Double {
        guard let duration, duration > 0 else { return 0 }
        return min(max(lastPlayedPosition / duration, 0), 1)
    }

    /// True once the item is at least 90% complete.
    var isWatched: Bool {
        progressFraction >= 0.9
    }

    /// True if there's a meaningful saved checkpoint. Resume remains available even
    /// past the conventional 90% "watched" threshold and disappears only at the end.
    var hasResumePoint: Bool {
        guard lastPlayedPosition > 5 else { return false }
        guard let duration, duration > 0 else { return true }
        return lastPlayedPosition < max(duration - 0.75, 0)
    }

    /// Convenience subtitle line built from whatever metadata exists.
    var subtitleLine: String {
        var parts: [String] = []
        // Prefer a structured episode ref when present.
        if let episode {
            parts.append(episode.label)
        } else if let s = metadata.season, let e = metadata.episode {
            parts.append(String(format: "S%02dE%02d", s, e))
        }
        if let year = metadata.year { parts.append(String(year)) }
        if let res = metadata.resolution { parts.append(res) }
        return parts.joined(separator: " · ")
    }

    /// True when this MediaItem represents a series episode.
    var isEpisode: Bool { episode != nil }

    /// A display title that, for episodes, leads with the show name.
    var displayTitle: String {
        if let seriesTitle, let episode {
            return "\(seriesTitle) · \(episode.label)"
        }
        return title
    }

    /// A short label for an episode (e.g. "S01E02 · Episode title"), or the plain
    /// title for non-episodes. Used by the up-next card.
    var episodeLabel: String? {
        guard let episode else { return nil }
        return "\(episode.label) · \(title)"
    }

    /// Whether this library item represents a series (a show or an episode of one).
    var isSeries: Bool {
        contentID?.type == .series || episode != nil || seriesTitle != nil
    }

    /// True when the item already carries a directly playable file/stream (SMB share,
    /// direct URL, or live channel) rather than something that needs stream resolution.
    var isDirectPlay: Bool {
        switch sourceType {
        case .smb, .directURL, .liveTV: return true
        case .realDebrid, .addon, .trakt: return false
        }
    }

    /// Builds a CatalogItem so this library item opens the full detail screen used by
    /// Discover and Home (season and episode rails for shows). Uses the show title
    /// for episodes.
    func asCatalogItem() -> CatalogItem {
        let showTitle = seriesTitle ?? title
        let cid = contentID ?? ContentID(type: isSeries ? .series : .movie)
        let resolved = ContentID(imdb: cid.imdb, tmdb: cid.tmdb, trakt: cid.trakt,
                                 addonItemID: cid.addonItemID,
                                 type: isSeries ? .series : .movie)
        return CatalogItem(
            contentID: resolved,
            title: showTitle,
            overview: nil,
            posterURL: posterURL,
            backdropURL: backdropURL ?? posterURL,
            year: metadata.year,
            rating: nil,
            genres: []
        )
    }
}

/// Lightweight reference to a specific episode, stored on a MediaItem so the
/// player can compute "next episode" and the library can group by show.
struct EpisodeRef: Codable, Hashable {
    var season: Int
    var number: Int
    var episodeTitle: String?

    var label: String { String(format: "S%02dE%02d", season, number) }
}

struct MediaMetadata: Codable, Hashable {
    var filename: String?
    var fileSize: Int64?
    var codec: String?
    var resolution: String?
    var season: Int?
    var episode: Int?
    var year: Int?
    /// Stable SMB identity used to rebuild the temporary localhost playback URL
    /// whenever the app or network connection changes.
    var smbShareID: UUID?
    var smbPath: String?

    init(
        filename: String? = nil,
        fileSize: Int64? = nil,
        codec: String? = nil,
        resolution: String? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        year: Int? = nil,
        smbShareID: UUID? = nil,
        smbPath: String? = nil
    ) {
        self.filename = filename
        self.fileSize = fileSize
        self.codec = codec
        self.resolution = resolution
        self.season = season
        self.episode = episode
        self.year = year
        self.smbShareID = smbShareID
        self.smbPath = smbPath
    }
}
