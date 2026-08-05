//
//  DeepLink.swift
//  Nova
//
//  Parses nova:// URLs into in-app destinations. Deep links power Shortcuts,
//  widgets, Top Shelf, and QR-based setup — anything that needs to jump straight to
//  a place in the app from outside it.
//
//  Supported forms:
//    nova://home                     -> Home tab
//    nova://discover                 -> Discover tab
//    nova://ai                       -> AI tab
//    nova://library                  -> Library tab
//    nova://settings                 -> Settings tab
//    nova://settings/sources         -> Settings tab, Sources screen
//    nova://movie/<contentKey>       -> open a movie's detail
//    nova://show/<contentKey>        -> open a show's detail
//    nova://continue                 -> Library tab (Continue Watching)
//
//  contentKey is the same stable key used everywhere else (e.g. "imdb:tt0111161"
//  or "tmdb:movie:27205"). Note the catalog placeholder URL "nova://catalog/<key>"
//  is an internal playback marker, not a navigation link, and is handled separately.
//

import Foundation

enum DeepLink: Equatable {
    case tab(AppTab)
    case settingsSources
    case content(contentKey: String, isShow: Bool)
    case continueWatching

    /// Parses a Nova URL. Astra and FrameTV schemes remain accepted so restored
    /// widgets, shortcuts, and bookmarks continue to work after the rename.
    static func parse(_ url: URL) -> DeepLink? {
        let supportedSchemes = ["nova", "astra", "frametv"]
        guard let scheme = url.scheme?.lowercased(), supportedSchemes.contains(scheme) else {
            return nil
        }

        // URL(string:) puts the first path segment in `host` for custom schemes,
        // e.g. nova://movie/tt123 -> host "movie", path "/tt123".
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
