//
//  PlaybackCoordinator.swift
//  Nova
//
//  Guarantees that only one video/audio player is ever active. Each player model
//  registers itself here when it starts; registering a new player immediately stops
//  the previous one. This prevents the situation where navigating from one video to
//  another (or auto-play picking a next item) leaves the old AVPlayer or VLC player
//  still playing in the background, producing two overlapping streams of audio/video.
//

import Foundation

/// Anything that can be force-stopped by the coordinator. Both PlayerModel and
/// VLCPlayerModel conform.
@MainActor
protocol StoppablePlayer: AnyObject {
    /// Stop playback and release resources. Must be safe to call more than once.
    func stopAndSave()
}

@MainActor
final class PlaybackCoordinator {
    static let shared = PlaybackCoordinator()
    private init() {}

    /// The currently active player, held weakly so it can deallocate normally.
    private weak var active: StoppablePlayer?

    /// Registers `player` as the active one, stopping any previous player first.
    func activate(_ player: StoppablePlayer) {
        if let previous = active, previous !== player {
            previous.stopAndSave()
        }
        active = player
    }

    /// Clears the active player if it is the one passed in.
    func resign(_ player: StoppablePlayer) {
        if active === player { active = nil }
    }

    /// Stops whatever is currently playing, if anything. Used by a global Stop control.
    func stopAll() {
        active?.stopAndSave()
        active = nil
    }

    /// Whether something is currently active.
    var hasActivePlayer: Bool { active != nil }
}
