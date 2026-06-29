//
//  PlaybackEngineRouter.swift
//  FrameTV
//
//  Decides which playback engine to use for a given item. AVPlayer is fast and
//  battery-efficient but only opens MP4/M4V/MOV and HLS. VLCKit plays everything
//  else (MKV, AVI, WebM, TS, and unusual codecs), so anything not known to be
//  AVPlayer-compatible is routed to VLC.
//

import Foundation

enum PlaybackEngineRouter {

    /// Extensions AVPlayer reliably plays.
    private static let avPlayerExtensions: Set<String> = ["mp4", "m4v", "mov"]

    /// Whether to use the VLC engine for this item, honoring the user's preferred
    /// built-in player profile (which can force VLC or force AVPlayer).
    static func shouldUseVLC(for item: MediaItem, preference: BuiltInPlayer = .auto) -> Bool {
        // Explicit user choices win, except that AVPlayer can't open formats it doesn't
        // support — in that case fall back to VLC regardless.
        if preference.forcesVLC { return true }
        if preference.forcesAVPlayer { return !isAVPlayerCompatible(item) ? true : false }

        // If we've seen an engine succeed for this exact title before, prefer it — but
        // never route to AVPlayer for a format it can't open.
        if let remembered = PlayerMemory.engine(for: item) {
            switch remembered {
            case .vlc:      return true
            case .avPlayer: return isAVPlayerCompatible(item) ? false : true
            }
        }

        return !isAVPlayerCompatible(item)
    }

    /// Whether AVPlayer can reliably open this item based on its container/extension.
    static func isAVPlayerCompatible(for item: MediaItem) -> Bool { isAVPlayerCompatible(item) }

    private static func isAVPlayerCompatible(_ item: MediaItem) -> Bool {
        let url = item.playbackURL
        let ext = url.pathExtension.lowercased()

        // HLS streams play great in AVPlayer.
        if ext == "m3u8" { return true }
        // Known AVPlayer-friendly containers stay on AVPlayer.
        if avPlayerExtensions.contains(ext) { return true }

        // Local SMB bridge URLs carry the real filename in the path; check that.
        if url.host == "127.0.0.1" {
            let lastComponent = url.lastPathComponent.lowercased()
            if avPlayerExtensions.contains((lastComponent as NSString).pathExtension) { return true }
            if lastComponent.hasSuffix(".m3u8") { return true }
        }

        // Everything else — MKV, AVI, WebM, TS, or no/unknown extension (common for
        // debrid and addon links) — is not known-compatible, so prefer VLC.
        return false
    }
}
