//
//  SourceType.swift
//  Nova
//
//  Defines the kinds of media sources the app understands.
//

import Foundation

enum SourceType: String, Codable, CaseIterable, Identifiable, Sendable {
    case smb
    case realDebrid
    case directURL
    case addon          // Stremio-protocol addons (Stremio, AIOStreams, Comet)
    case trakt          // content surfaced from a Trakt list / watchlist
    case liveTV         // live channel from an addon's tv catalog
    case jellyfin       // a user-configured Jellyfin server
    case plex           // a user-configured Plex server
    case emby           // a user-configured Emby server

    var id: String { rawValue }

    /// Human-readable name shown in the UI.
    var displayName: String {
        switch self {
        case .smb:          return "SMB Share"
        case .realDebrid:   return "Real-Debrid"
        case .directURL:    return "Direct URL"
        case .addon:        return "Addon"
        case .trakt:        return "Trakt"
        case .liveTV:       return "Live TV"
        case .jellyfin:     return "Jellyfin"
        case .plex:         return "Plex"
        case .emby:         return "Emby"
        }
    }

    /// SF Symbol used on cards and rows.
    var systemImage: String {
        switch self {
        case .smb:          return "externaldrive.connected.to.line.below"
        case .realDebrid:   return "arrow.down.circle"
        case .directURL:    return "link"
        case .addon:        return "puzzlepiece.extension"
        case .liveTV:       return "dot.radiowaves.left.and.right"
        case .trakt:        return "checkmark.seal"
        case .jellyfin:     return "play.tv"
        case .plex:         return "play.square.stack"
        case .emby:         return "rectangle.stack.badge.play"
        }
    }
}
