//
//  DeepLink.swift
//  FrameTV
//
//  Parses frametv:// URLs into in-app destinations. Deep links power Shortcuts,
//  widgets, Top Shelf, and QR-based setup — anything that needs to jump straight to
//  a place in the app from outside it.
//
//  Supported forms:
//    frametv://home                     -> Home tab
//    frametv://discover                 -> Discover tab
//    frametv://ai                       -> AI tab
//    frametv://library                  -> Library tab
//    frametv://settings                 -> Settings tab
//    frametv://settings/sources         -> Settings tab, Sources screen
//    frametv://movie/<contentKey>       -> open a movie's detail
//    frametv://show/<contentKey>        -> open a show's detail
//    frametv://continue                 -> Library tab (Continue Watching)
//
//  contentKey is the same stable key used everywhere else (e.g. "imdb:tt0111161"
//  or "tmdb:movie:27205"). Note the catalog placeholder URL "frametv://catalog/<key>"
//  is an internal playback marker, not a navigation link, and is handled separately.
//

import Foundation

enum DeepLink: Equatable {
    case tab(AppTab)
    case settingsSources
    case content(contentKey: String, isShow: Bool)
    case continueWatching

    /// Parses a frametv:// URL. Returns nil for anything not recognized.
    static func parse(_ url: URL) -> DeepLink? {
        guard url.scheme?.lowercased() == "frametv" else { return nil }

        // URL(string:) puts the first path segment in `host` for custom schemes,
        // e.g. frametv://movie/tt123 -> host "movie", path "/tt123".
        let head = (url.host ?? "").lowercased()
        let tail = url.pathComponents.filter { $0 != "/" }

        switch head {
        case "home":     return .tab(.home)
        case "discover": return .tab(.discover)
        case "ai":       return .tab(.ai)
        case "library":  return .tab(.library)
        case "continue": return .continueWatching
        case "settings":
            if tail.first?.lowercased() == "sources" { return .settingsSources }
            return .tab(.settings)
        case "movie":
            guard let key = tail.first else { return nil }
            return .content(contentKey: key, isShow: false)
        case "show", "series", "tv":
            guard let key = tail.first else { return nil }
            return .content(contentKey: key, isShow: true)
        default:
            return nil
        }
    }
}
