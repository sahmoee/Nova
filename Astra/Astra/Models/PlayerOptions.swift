//
//  PlayerOptions.swift
//  Astra
//
//  The set of players Astra can hand a stream to. Two kinds:
//
//  Built-in players run inside Astra. On Apple platforms only two engines can be
//  embedded — Apple's AVPlayer and VLCKit (which wraps FFmpeg) — so the built-in
//  options are distinct, purpose-tuned configurations of those two engines rather
//  than separate third-party SDKs (which aren't available on iOS/tvOS).
//
//  External players are separate apps the user has installed. Astra hands them the
//  stream URL via the app's documented custom URL scheme; playback then happens in
//  that app. This is iPhone/iPad only — tvOS has no such inter-app handoff.
//

import Foundation
#if os(iOS)
import UIKit
#endif

// MARK: - Built-in engines

/// A player that runs inside Astra. Each case maps to one of the two embeddable
/// engines with a specific tuning profile.
enum BuiltInPlayer: String, CaseIterable, Codable, Identifiable {
    case auto            // pick AVPlayer or VLC automatically by format (default)
    case appleNative     // force AVPlayer — most efficient, MP4/MOV/HLS only
    case vlcCompatible   // force VLCKit — plays virtually any format/codec
    case vlcHardware     // VLCKit tuned to prefer hardware decoding (smoother 4K)
    case vlcNetworkTuned // VLCKit with a larger network cache (better on slow links)

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto:            return "Automatic"
        case .appleNative:     return "Apple Native (AVPlayer)"
        case .vlcCompatible:   return "VLC Compatibility"
        case .vlcHardware:     return "VLC (Hardware Decode)"
        case .vlcNetworkTuned: return "VLC (Slow Connection)"
        }
    }

    var detail: String {
        switch self {
        case .auto:            return "Use the best engine for each file. Recommended."
        case .appleNative:     return "Most battery-efficient. MP4, MOV, and HLS only."
        case .vlcCompatible:   return "Plays almost any format or codec, including MKV."
        case .vlcHardware:     return "Prefers hardware decoding for smoother 4K and HEVC."
        case .vlcNetworkTuned: return "Buffers more for unreliable or slow connections."
        }
    }

    var systemImage: String {
        switch self {
        case .auto:            return "wand.and.stars"
        case .appleNative:     return "play.tv"
        case .vlcCompatible:   return "film"
        case .vlcHardware:     return "bolt.fill"
        case .vlcNetworkTuned: return "wifi.exclamationmark"
        }
    }

    /// Extra network cache (ms) to pass to VLC for this profile; nil for AVPlayer/auto.
    var vlcNetworkCacheMs: Int? {
        switch self {
        case .vlcNetworkTuned: return 5000
        case .vlcHardware, .vlcCompatible: return 1500
        default: return nil
        }
    }

    /// Whether this profile forces VLC regardless of format.
    var forcesVLC: Bool {
        switch self {
        case .vlcCompatible, .vlcHardware, .vlcNetworkTuned: return true
        default: return false
        }
    }

    /// Whether this profile forces AVPlayer (only valid for AVPlayer-compatible files).
    var forcesAVPlayer: Bool { self == .appleNative }

    /// Whether VLC should prefer hardware decoding for this profile.
    var prefersHardwareDecoding: Bool { self == .vlcHardware }
}

// MARK: - External apps

/// A third-party player app Astra can hand a stream to (iOS only). Each builds a
/// launch URL from the documented scheme of that app.
enum ExternalPlayer: String, CaseIterable, Codable, Identifiable {
    case infuse
    case vlc
    case outplayer
    case nplayer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .infuse:    return "Infuse"
        case .vlc:       return "VLC"
        case .outplayer: return "Outplayer"
        case .nplayer:   return "nPlayer"
        }
    }

    var detail: String {
        switch self {
        case .infuse:    return "Polished playback with rich format support."
        case .vlc:       return "The standalone VLC app. Plays everything."
        case .outplayer: return "Fast, format-friendly player."
        case .nplayer:   return "Advanced player with audio passthrough."
        }
    }

    var systemImage: String { "arrow.up.forward.app" }

    /// The URL scheme used only to detect whether the app is installed.
    private var probeURL: URL? {
        switch self {
        case .infuse:    return URL(string: "infuse://")
        case .vlc:       return URL(string: "vlc://")
        case .outplayer: return URL(string: "outplayer://")
        case .nplayer:   return URL(string: "nplayer-http://")
        }
    }

    /// Builds the launch URL that opens the given stream in this app.
    func launchURL(for stream: URL) -> URL? {
        let raw = stream.absoluteString
        let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw
        switch self {
        case .infuse:
            return URL(string: "infuse://x-callback-url/play?url=\(encoded)")
        case .vlc:
            return URL(string: "vlc://\(raw)")
        case .outplayer:
            return URL(string: "outplayer://\(raw)")
        case .nplayer:
            // nPlayer opens http(s) streams via its scheme-swapped URL.
            if let comps = URLComponents(url: stream, resolvingAgainstBaseURL: false) {
                var c = comps
                c.scheme = (stream.scheme == "https") ? "nplayer-https" : "nplayer-http"
                return c.url
            }
            return nil
        }
    }

    #if os(iOS)
    /// Whether the app appears to be installed (its scheme can be opened).
    @MainActor
    var isInstalled: Bool {
        guard let probeURL else { return false }
        return UIApplication.shared.canOpenURL(probeURL)
    }

    /// Opens the stream in this external app. Returns false if it couldn't launch.
    @MainActor
    @discardableResult
    func open(_ stream: URL) -> Bool {
        guard let url = launchURL(for: stream) else { return false }
        guard UIApplication.shared.canOpenURL(url) else { return false }
        UIApplication.shared.open(url)
        return true
    }
    #endif
}
