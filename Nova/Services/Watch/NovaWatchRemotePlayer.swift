import Foundation
import AVFoundation
#if canImport(VLCKitSPM)
import VLCKitSPM
#endif

@MainActor
protocol NovaWatchRemotePlayer: AnyObject {
    func watchStatus(sessionID: UUID) -> NovaWatchPlayer?
    func applyWatchCommand(_ command: NovaWatchCommand) throws
}

extension PlayerModel: NovaWatchRemotePlayer {
    func watchStatus(sessionID: UUID) -> NovaWatchPlayer? {
        guard state == .ready, player.currentItem?.status == .readyToPlay, !didFinish else { return nil }
        let position = player.currentTime().seconds
        guard position.isFinite, position >= 0 else { return nil }
        return NovaWatchPlayer(sessionID: sessionID, title: String(item.displayTitle.prefix(180)), playing: player.timeControlStatus == .playing,
            position: position, duration: duration > 0 && duration.isFinite ? duration : nil,
            volume: Double(player.volume), canSeek: !(player.currentItem?.seekableTimeRanges.isEmpty ?? true), observedAt: Date())
    }
    func applyWatchCommand(_ command: NovaWatchCommand) throws {
        guard let status = watchStatus(sessionID: command.playerSessionID ?? UUID()) else { throw NovaWatchFailure.disconnected }
        switch command.action {
        case .setPlaying: command.flag == true ? play() : pause()
        case .seek:
            guard status.canSeek, let value = command.value, let duration = status.duration, value <= duration,
                  player.currentItem?.seekableTimeRanges.contains(where: { CMTimeRangeContainsTime($0.timeRangeValue, time: CMTime(seconds: value, preferredTimescale: 600)) }) == true else { throw NovaWatchFailure.invalid }
            player.seek(to: CMTime(seconds: value, preferredTimescale: 600))
        case .setVolume: player.volume = Float(command.value ?? status.volume ?? 1)
        default: throw NovaWatchFailure.invalid
        }
    }
}

#if canImport(VLCKitSPM)
extension VLCPlayerModel: NovaWatchRemotePlayer {
    func watchStatus(sessionID: UUID) -> NovaWatchPlayer? {
        guard state == .ready, !didFinish, duration.isFinite, currentTime.isFinite else { return nil }
        return NovaWatchPlayer(sessionID: sessionID, title: String(item.displayTitle.prefix(180)), playing: mediaPlayer.isPlaying,
            position: max(0, currentTime), duration: duration > 0 ? duration : nil,
            volume: mediaPlayer.audio.flatMap { (0...100).contains($0.volume) ? Double($0.volume) / 100 : nil }, canSeek: mediaPlayer.isSeekable && duration > 0, observedAt: Date())
    }
    func applyWatchCommand(_ command: NovaWatchCommand) throws {
        guard let status = watchStatus(sessionID: command.playerSessionID ?? UUID()) else { throw NovaWatchFailure.disconnected }
        switch command.action {
        case .setPlaying: if mediaPlayer.isPlaying != (command.flag == true) { togglePlayPause() }
        case .seek:
            guard status.canSeek, let value = command.value, value <= (status.duration ?? 0) else { throw NovaWatchFailure.invalid }
            seek(to: value)
        case .setVolume:
            guard let audio = mediaPlayer.audio, let value = command.value else { throw NovaWatchFailure.invalid }
            audio.volume = Int32((value * 100).rounded())
        default: throw NovaWatchFailure.invalid
        }
    }
}
#endif
