//
//  SourceType.swift
//  FrameTV
//
//  Defines the kinds of media sources the app understands.
//

import Foundation

enum SourceType: String, Codable, CaseIterable, Identifiable {
    case smb
    case realDebrid
    case directURL
    case publicDomain
    case addon          // Stremio-protocol addons (Stremio, AIOStreams, Comet)
    case trakt          // content surfaced from a Trakt list / watchlist

    var id: String { rawValue }

    /// Human-readable name shown in the UI.
    var displayName: String {
        switch self {
        case .smb:          return "SMB Share"
        case .realDebrid:   return "Real-Debrid"
        case .directURL:    return "Direct URL"
        case .publicDomain: return "Public Domain"
        case .addon:        return "Addon"
        case .trakt:        return "Trakt"
        }
    }

    /// SF Symbol used on cards and rows.
    var systemImage: String {
        switch self {
        case .smb:          return "externaldrive.connected.to.line.below"
        case .realDebrid:   return "arrow.down.circle"
        case .directURL:    return "link"
        case .publicDomain: return "building.columns"
        case .addon:        return "puzzlepiece.extension"
        case .trakt:        return "checkmark.seal"
        }
    }
}
