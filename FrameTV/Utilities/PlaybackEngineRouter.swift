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

    /// Whether to use the VLC engine for this item.
    static func shouldUseVLC(for item: MediaItem) -> Bool {
        let url = item.playbackURL
        let ext = url.pathExtension.lowercased()

        // HLS streams play great in AVPlayer.
        if ext == "m3u8" { return false }
        // Known AVPlayer-friendly containers stay on AVPlayer.
        if avPlayerExtensions.contains(ext) { return false }

        // Local SMB bridge URLs carry the real filename in the path; check that.
        if url.host == "127.0.0.1" {
            let lastComponent = url.lastPathComponent.lowercased()
            if avPlayerExtensions.contains((lastComponent as NSString).pathExtension) { return false }
            if lastComponent.hasSuffix(".m3u8") { return false }
        }

        // Everything else — MKV, AVI, WebM, TS, or no/unknown extension (common for
        // debrid and addon links) — goes to VLC, which can handle it.
        return true
    }
}
