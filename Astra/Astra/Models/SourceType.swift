//
//  SourceType.swift
//  Astra
//
//  Defines the kinds of media sources the app understands.
//

import Foundation

enum SourceType: String, Codable, CaseIterable, Identifiable {
    case smb
    case realDebrid
    case directURL
    case addon          // Stremio-protocol addons (Stremio, AIOStreams, Comet)
    case trakt          // content surfaced from a Trakt list / watchlist
    case liveTV         // live channel from an addon's tv catalog

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
        }
    }
}
