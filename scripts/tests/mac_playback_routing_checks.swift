// Standalone router checks. Compile this harness with the production router;
// these stand-ins isolate routing from persisted app data and UI frameworks.
import Foundation

struct MediaItem { let playbackURL: URL }
enum PlayerMemory {
    enum Engine { case vlc, avPlayer }
    static func engine(for item: MediaItem) -> Engine? { nil }
}

@main
struct RoutingChecks {
    static func main() {
        let urls = ["https://example.test/video.mp4", "https://example.test/live.m3u8", "https://example.test/stream", "https://example.test/video.mkv"]
        var count = 0
        for (index, raw) in urls.enumerated() {
            let item = MediaItem(playbackURL: URL(string: raw)!)
            for preference in BuiltInPlayer.allCases {
                #if targetEnvironment(macCatalyst)
                precondition(!PlaybackEngineRouter.shouldUseVLC(for: item, preference: preference))
                #else
                let expected = preference.forcesVLC || index >= 2
                precondition(PlaybackEngineRouter.shouldUseVLC(for: item, preference: preference) == expected)
                #endif
                count += 1
            }
        }
        #if targetEnvironment(macCatalyst)
        precondition(BuiltInPlayer.availableCases == [.appleNative])
        precondition(!BuiltInPlayer.allowsPreferenceSelection, "Mac engine row cannot write cloud preferences")
        precondition(!PlaybackEngineRouter.shouldHandOffToExternalPlayer(preferred: true))
        #else
        precondition(BuiltInPlayer.availableCases == BuiltInPlayer.allCases)
        precondition(BuiltInPlayer.allowsPreferenceSelection)
        precondition(PlaybackEngineRouter.shouldHandOffToExternalPlayer(preferred: true))
        #endif
        precondition(!PlaybackEngineRouter.shouldHandOffToExternalPlayer(preferred: false))
        precondition(PlaybackEngineRouter.macPlaybackFailureGuidance.contains("MKV"))
        precondition(PlaybackEngineRouter.macPlaybackFailureGuidance.contains("embedded VLC is unavailable"))
        print("Passed \(count + 6) playback routing checks")
    }
}
