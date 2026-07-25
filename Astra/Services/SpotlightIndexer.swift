//
//  SpotlightIndexer.swift
//  Astra
//
//  Indexes the user's library into iOS Spotlight so they can search their movies and
//  shows from the home screen. Tapping a result opens Astra via a astra:// deep
//  link to that title.
//
//  iOS only — CoreSpotlight is not available on tvOS, so the whole type compiles to a
//  no-op shim there, letting call sites stay platform-agnostic.
//

import Foundation

#if os(iOS)
// CoreSpotlight isn't Sendable-audited yet; `@preconcurrency` suppresses the
// spurious Sendable warnings for its types (CSSearchableIndex / CSSearchableItem)
// captured in the completion-handler closures below.
@preconcurrency import CoreSpotlight
import UniformTypeIdentifiers

enum SpotlightIndexer {
    /// Domain used so we can clear just Astra's items if needed.
    private static let domain = "com.astra.library"

    /// Replaces the Spotlight index with the current library. Cheap to call on library
    /// changes; CoreSpotlight de-dupes by identifier.
    static func reindex(_ items: [MediaItem]) {
        let searchable = items.compactMap(makeItem)
        let index = CSSearchableIndex.default()
        // Clear our domain first, then add the current set, so removed items disappear.
        index.deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in
            guard !searchable.isEmpty else { return }
            index.indexSearchableItems(searchable) { _ in }
        }
    }

    /// Removes everything Astra put in Spotlight (e.g. on library clear).
    static func clear() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in }
    }

    private static func makeItem(_ item: MediaItem) -> CSSearchableItem? {
        guard let contentID = item.contentID else { return nil }

        let attrs = CSSearchableItemAttributeSet(contentType: UTType.movie)
        attrs.title = item.seriesTitle ?? item.title

        // Build a short subtitle: type + year, e.g. "Movie · 2017" or "Show · 2019".
        var parts: [String] = [contentID.type == .series ? "Show" : "Movie"]
        if let year = item.metadata.year { parts.append(String(year)) }
        attrs.contentDescription = parts.joined(separator: " · ")

        // Keywords help fuzzy matching.
        var keywords = [item.title]
        if let series = item.seriesTitle { keywords.append(series) }
        attrs.keywords = keywords

        if let poster = item.posterURL { attrs.thumbnailURL = poster }

        // The identifier doubles as the deep-link path: open this exact title.
        let isShow = contentID.type == .series
        let identifier = "astra://\(isShow ? "show" : "movie")/\(contentID.stableKey)"

        return CSSearchableItem(
            uniqueIdentifier: identifier,
            domainIdentifier: domain,
            attributeSet: attrs
        )
    }

    /// Pulls the astra:// deep-link URL out of a Spotlight result's activity.
    static func deepLinkURL(from userInfo: [AnyHashable: Any]) -> URL? {
        guard let id = userInfo[CSSearchableItemActivityIdentifier] as? String else { return nil }
        return URL(string: id)
    }
}

#else

// tvOS shim: no Spotlight, so these do nothing.
enum SpotlightIndexer {
    static func reindex(_ items: [MediaItem]) {}
    static func clear() {}
    static func deepLinkURL(from userInfo: [AnyHashable: Any]) -> URL? { nil }
}

#endif
