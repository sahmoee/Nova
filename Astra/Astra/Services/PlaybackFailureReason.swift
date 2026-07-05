//
//  PlaybackFailureReason.swift
//  Astra
//
//  A standardized set of reasons playback can fail, so the player, retry flow, and
//  diagnostics all speak the same language. Each case carries a user-facing message
//  and a hint about whether trying a different stream or engine is likely to help.
//

import Foundation

enum PlaybackFailureReason: Equatable {
    case unsupportedCodec
    case expiredURL
    case networkTimeout
    case vlcInitFailure
    case avPlayerFailure
    case smbAuth
    case noStream
    case addonTimeout
    case unknown(String)

    /// A short, user-facing description of what went wrong.
    var message: String {
        switch self {
        case .unsupportedCodec: return "This file's format isn't supported by the current player."
        case .expiredURL:       return "The stream link expired before playback could start."
        case .networkTimeout:   return "The connection timed out while loading the stream."
        case .vlcInitFailure:   return "The VLC player couldn't start for this file."
        case .avPlayerFailure:  return "The Apple player couldn't play this file."
        case .smbAuth:          return "Couldn't sign in to the SMB share for this file."
        case .noStream:         return "No playable stream was found."
        case .addonTimeout:     return "The source took too long to respond."
        case .unknown(let m):   return m.isEmpty ? "Playback failed for an unknown reason." : m
        }
    }

    /// SF Symbol summarizing the failure, for diagnostics/recovery UI.
    var systemImage: String {
        switch self {
        case .unsupportedCodec: return "exclamationmark.triangle"
        case .expiredURL:       return "clock.badge.xmark"
        case .networkTimeout:   return "wifi.exclamationmark"
        case .vlcInitFailure, .avPlayerFailure: return "play.slash"
        case .smbAuth:          return "lock.trianglebadge.exclamationmark"
        case .noStream:         return "magnifyingglass"
        case .addonTimeout:     return "hourglass.bottomhalf.filled"
        case .unknown:          return "questionmark.circle"
        }
    }

    /// Whether trying a *different stream* is likely to help (vs. the same stream
    /// in a different engine). Codec issues favor switching engines; expired/timeout
    /// favor a different stream.
    var suggestsDifferentStream: Bool {
        switch self {
        case .expiredURL, .networkTimeout, .noStream, .addonTimeout, .smbAuth: return true
        case .unsupportedCodec, .vlcInitFailure, .avPlayerFailure, .unknown:   return false
        }
    }

    /// Whether trying the *other engine* (VLC <-> AVPlayer) is likely to help.
    var suggestsOtherEngine: Bool {
        switch self {
        case .unsupportedCodec, .vlcInitFailure, .avPlayerFailure: return true
        default: return false
        }
    }

    /// Best-effort classification of a raw error/message into a reason.
    static func classify(_ raw: String) -> PlaybackFailureReason {
        let s = raw.lowercased()
        if s.contains("codec") || s.contains("format") || s.contains("unsupported") { return .unsupportedCodec }
        if s.contains("expired") || s.contains("410") || s.contains("403") { return .expiredURL }
        if s.contains("timed out") || s.contains("timeout") || s.contains("-1001") { return .networkTimeout }
        if s.contains("vlc") { return .vlcInitFailure }
        if s.contains("smb") || s.contains("logon") || s.contains("auth") { return .smbAuth }
        if s.contains("no stream") || s.contains("not found") { return .noStream }
        return .unknown(raw)
    }
}
