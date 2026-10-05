//
//  NowPlayingStore.swift
//  Nova
//
//  Tracks what's currently playing so a "Now Playing" mini-bar can appear above the
//  tab bar. Tapping it returns to the player. Cleared when playback ends or the user
//  leaves the player. This is in-memory only (a live session concept, not persisted).
//

import SwiftUI
import Combine

@MainActor
final class NowPlayingStore: ObservableObject {
    static let shared = NowPlayingStore()

    /// The item currently being played, if any.
    @Published private(set) var current: MediaItem?
    /// Whether playback is actively playing (vs paused).
    @Published var isPlaying: Bool = false
    /// Fractional progress 0...1 for the mini-bar's progress line.
    @Published var progress: Double = 0
    /// Whether a full player screen is currently on screen. While true, the mini-bar
    /// is suppressed — the bar is only for when the user has left the player.
    @Published var playerPresented: Bool = false

    private init() {}

    func begin(_ item: MediaItem, initialProgress: Double = 0) {
        current = item
        isPlaying = true
        // FIX: guard non-finite values (position/duration math can yield NaN when a
        // stream has no known duration); NaN slipped through min/max clamping and
        // rendered a broken/full progress line.
        progress = initialProgress.isFinite ? max(0, min(1, initialProgress)) : 0
        playerPresented = true
    }

    func update(progress: Double, isPlaying: Bool) {
        // FIX: same non-finite guard as begin(); keep the last good value on NaN.
        // Players report time several times a second. Publishing only visible changes
        // (a fifth of a percent, or a play/pause flip) keeps every observer of this
        // store — including the root navigation — from re-rendering during playback.
        if progress.isFinite {
            let clamped = max(0, min(1, progress))
            if abs(clamped - self.progress) >= 0.002 || (clamped == 0) != (self.progress == 0) || clamped == 1 {
                if clamped != self.progress { self.progress = clamped }
            }
        }
        if self.isPlaying != isPlaying { self.isPlaying = isPlaying }
    }

    /// The user left the player screen but playback state should persist so the
    /// Now Playing / Resume bar stays visible. Keeps `current` and progress; only
    /// marks the full player as no longer on screen. The bar shows until an explicit
    /// stop() or the app closes.
    func minimize() {
        // Playback pauses when the player is left, so reflect that in the bar.
        isPlaying = false
        playerPresented = false
    }

    /// Full stop: the user explicitly ended playback (back/exit/stop). Clears the bar.
    func clear() {
        current = nil
        isPlaying = false
        progress = 0
        playerPresented = false
    }
}
