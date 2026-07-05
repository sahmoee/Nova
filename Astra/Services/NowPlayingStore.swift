//
//  NowPlayingStore.swift
//  Astra
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

    func begin(_ item: MediaItem) {
        current = item
        isPlaying = true
        progress = 0
        playerPresented = true
    }

    func update(progress: Double, isPlaying: Bool) {
        self.progress = max(0, min(1, progress))
        self.isPlaying = isPlaying
    }

    func clear() {
        current = nil
        isPlaying = false
        progress = 0
        playerPresented = false
    }
}
