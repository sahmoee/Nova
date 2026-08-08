//
//  PersonalizedHomeEngine.swift
//  Nova
//
//  On-device personalization for the Apple TV-style Home experience. It creates
//  useful rails from the user's own library without sending viewing history away.
//

import Foundation

enum SmartHomeRailKind: String, Hashable {
    case topPicks
    case finishTonight
    case becauseYouWatched
    case bingeNext
    case unwatchedFavorites
    case highQuality
    case personalMedia
    case recentlyWatched
    case rediscover
    case recentlyAdded
}

struct SmartHomeRail: Identifiable, Hashable {
    let kind: SmartHomeRailKind
    let title: String
    let subtitle: String?
    let systemImage: String
    let items: [MediaItem]

    var id: String { kind.rawValue }
}

enum PersonalizedHomeEngine {
    @MainActor
    static func rails(library: LibraryStore, profile: ViewingProfile) -> [SmartHomeRail] {
        let visible = library.items.filter { !$0.isHidden }
        guard !visible.isEmpty else { return [] }

        var rails: [SmartHomeRail] = []
        append(&rails, kind: .topPicks,
               title: "Top Picks for \(profile.name)",
               subtitle: "Based on favorites, queue, and recent viewing",
               systemImage: "sparkles.tv",
               items: topPicks(from: visible, library: library, profile: profile))

        append(&rails, kind: .finishTonight,
               title: "Finish Tonight",
               subtitle: "In-progress titles with a manageable amount left",
               systemImage: "moon.stars.fill",
               items: finishTonight(from: visible))

        if let anchor = library.recentlyWatched.first {
            append(&rails, kind: .becauseYouWatched,
                   title: "Because You Watched \(anchor.seriesTitle ?? anchor.title)",
                   subtitle: "Similar titles already available in your library",
                   systemImage: "wand.and.stars",
                   items: becauseYouWatched(anchor: anchor, candidates: visible))
        }

        append(&rails, kind: .bingeNext,
               title: "Binge Next",
               subtitle: "Series and episodes ready to continue",
               systemImage: "rectangle.stack.badge.play.fill",
               items: bingeNext(from: visible))

        append(&rails, kind: .unwatchedFavorites,
               title: "Favorites You Haven’t Finished",
               subtitle: nil,
               systemImage: "star.fill",
               items: visible.filter { $0.isFavorite && !$0.isWatched })

        append(&rails, kind: .highQuality,
               title: "4K & High Quality",
               subtitle: "The best-quality copies in your library",
               systemImage: "4k.tv.fill",
               items: highQuality(from: visible))

        append(&rails, kind: .personalMedia,
               title: "Personal & Network Media",
               subtitle: "SMB shares and direct links",
               systemImage: "externaldrive.connected.to.line.below",
               items: visible.filter { $0.sourceType == .smb || $0.sourceType == .directURL })

        append(&rails, kind: .recentlyWatched,
               title: "Watch History",
               subtitle: "Jump back into something you played recently",
               systemImage: "clock.arrow.circlepath",
               items: library.recentlyWatched)

        append(&rails, kind: .rediscover,
               title: "Rediscover Your Library",
               subtitle: "Older additions you have not watched yet",
               systemImage: "arrow.triangle.2.circlepath",
               items: rediscover(from: visible))

        append(&rails, kind: .recentlyAdded,
               title: "Recently Added",
               subtitle: nil,
               systemImage: "clock.badge.plus",
               items: library.recentlyAdded)

        return rails
    }

    @MainActor
    static func upNext(library: LibraryStore) -> [MediaItem] {
        deduplicated(library.continueWatching + library.queuedItems)
    }

    /// Produces a Home feed where a title appears only once across all rails. A
    /// small library should become a short, useful feed instead of repeating the
    /// same artwork under several slightly different headings.
    @MainActor
    static func distinctRails(library: LibraryStore,
                              profile: ViewingProfile,
                              excluding excludedItems: [MediaItem] = []) -> [SmartHomeRail] {
        var seen = Set(excludedItems.map(displayIdentity))
        return rails(library: library, profile: profile).compactMap { rail in
            let uniqueItems = rail.items.filter { seen.insert(displayIdentity($0)).inserted }
            guard !uniqueItems.isEmpty else { return nil }
            return SmartHomeRail(kind: rail.kind,
                                 title: rail.title,
                                 subtitle: rail.subtitle,
                                 systemImage: rail.systemImage,
                                 items: uniqueItems)
        }
    }

    private static func append(_ rails: inout [SmartHomeRail],
                               kind: SmartHomeRailKind,
                               title: String,
                               subtitle: String?,
                               systemImage: String,
                               items: [MediaItem]) {
        let collapsed = deduplicated(items).prefix(20).map { $0 }
        guard !collapsed.isEmpty else { return }
        rails.append(SmartHomeRail(kind: kind,
                                   title: title,
                                   subtitle: subtitle,
                                   systemImage: systemImage,
                                   items: collapsed))
    }

    @MainActor
    private static func topPicks(from items: [MediaItem],
                                 library: LibraryStore,
                                 profile: ViewingProfile) -> [MediaItem] {
        let queue = Set(library.queueIDs)
        let preferred = Set(profile.preferredTags.map { $0.lowercased() })
        return items
            .filter { !$0.isWatched }
            .sorted { score($0, queue: queue, preferred: preferred) > score($1, queue: queue, preferred: preferred) }
    }

    private static func score(_ item: MediaItem, queue: Set<UUID>, preferred: Set<String>) -> Int {
        var value = 0
        if item.isFavorite { value += 40 }
        if queue.contains(item.id) { value += 35 }
        if item.hasResumePoint { value += 30 }
        if item.isSeries { value += 8 }
        if item.posterURL != nil { value += 4 }
        if item.addedDate > Date().addingTimeInterval(-60 * 60 * 24 * 30) { value += 12 }
        if item.tags.contains(where: { preferred.contains($0.lowercased()) }) { value += 28 }
        if let played = item.lastPlayedDate {
            value += max(0, 14 - Calendar.current.dateComponents([.day], from: played, to: Date()).day.orZero)
        }
        return value
    }

    private static func finishTonight(from items: [MediaItem]) -> [MediaItem] {
        items.filter { item in
            guard item.hasResumePoint, let duration = item.duration, duration > 0 else { return false }
            let remaining = duration - item.lastPlayedPosition
            return remaining > 0 && remaining <= 2.5 * 60 * 60
        }
        .sorted { remaining($0) < remaining($1) }
    }

    private static func remaining(_ item: MediaItem) -> TimeInterval {
        max((item.duration ?? .greatestFiniteMagnitude) - item.lastPlayedPosition, 0)
    }

    private static func becauseYouWatched(anchor: MediaItem, candidates: [MediaItem]) -> [MediaItem] {
        let anchorTags = Set(anchor.tags.map { $0.lowercased() })
        return candidates
            .filter { $0.contentKey != anchor.contentKey && !$0.isWatched }
            .sorted { similarity($0, anchor: anchor, anchorTags: anchorTags) > similarity($1, anchor: anchor, anchorTags: anchorTags) }
    }

    private static func similarity(_ item: MediaItem, anchor: MediaItem, anchorTags: Set<String>) -> Int {
        var value = 0
        if item.sourceType == anchor.sourceType { value += 5 }
        if item.isSeries == anchor.isSeries { value += 12 }
        if item.isFavorite { value += 7 }
        let overlap = item.tags.map { $0.lowercased() }.filter(anchorTags.contains).count
        value += overlap * 20
        if let a = anchor.metadata.year, let b = item.metadata.year, abs(a - b) <= 5 { value += 4 }
        if item.seriesTitle != nil, item.seriesTitle == anchor.seriesTitle { value += 30 }
        return value
    }

    private static func bingeNext(from items: [MediaItem]) -> [MediaItem] {
        let series = items.filter { $0.isSeries && !$0.isWatched }
            .sorted {
                if $0.hasResumePoint != $1.hasResumePoint { return $0.hasResumePoint }
                return ($0.lastPlayedDate ?? $0.addedDate) > ($1.lastPlayedDate ?? $1.addedDate)
            }
        return deduplicated(series)
    }

    private static func highQuality(from items: [MediaItem]) -> [MediaItem] {
        items.filter { item in
            let quality = (item.metadata.resolution ?? "").lowercased()
            return quality.contains("4k") || quality.contains("2160") || quality.contains("uhd") || quality.contains("1080")
        }
        .sorted { qualityScore($0) > qualityScore($1) }
    }

    private static func qualityScore(_ item: MediaItem) -> Int {
        let quality = (item.metadata.resolution ?? "").lowercased()
        if quality.contains("4k") || quality.contains("2160") || quality.contains("uhd") { return 3 }
        if quality.contains("1080") { return 2 }
        if quality.contains("720") { return 1 }
        return 0
    }

    private static func rediscover(from items: [MediaItem]) -> [MediaItem] {
        items.filter { !$0.isWatched && !$0.hasResumePoint }
            .sorted { $0.addedDate < $1.addedDate }
    }

    private static func deduplicated(_ items: [MediaItem]) -> [MediaItem] {
        var seen = Set<String>()
        return items.filter { seen.insert(displayIdentity($0)).inserted }
    }

    /// Content IDs are preferred, but restored libraries and different addons can
    /// represent the same title with different URLs. The semantic fallback catches
    /// those copies while keeping individual series episodes distinct.
    private static func displayIdentity(_ item: MediaItem) -> String {
        if let contentID = item.contentID, !contentID.stableKey.hasPrefix("unknown:") {
            if let episode = item.episode {
                return "\(contentID.stableKey)|s\(episode.season)e\(episode.number)"
            }
            return contentID.stableKey
        }
        if let episode = item.episode {
            return "episode:\((item.seriesTitle ?? item.title).normalizedIdentity)|s\(episode.season)e\(episode.number)"
        }
        return "title:\(item.title.normalizedIdentity)|\(item.metadata.year.map(String.init) ?? "")"
    }
}

private extension String {
    var normalizedIdentity: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private extension Optional where Wrapped == Int {
    var orZero: Int { self ?? 0 }
}
