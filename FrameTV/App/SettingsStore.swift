//
//  SettingsStore.swift
//  FrameTV
//
//  Lightweight user-preferences store backed by UserDefaults. Holds non-secret
//  settings only (secrets live in Keychain).
//

import SwiftUI
import Combine

@MainActor
final class SettingsStore: ObservableObject {

    private let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Key {
        static let resumePlayback = "settings.resumePlayback"
        static let requireLegalConfirmation = "settings.requireLegalConfirmation"
        static let defaultQuality = "settings.defaultQuality"
        static let didSeedMockData = "settings.didSeedMockData"
        static let autoPlayNext = "settings.autoPlayNext"
        static let skipIntro = "settings.skipIntro"
        static let autoSkipIntro = "settings.autoSkipIntro"
        static let skipOutro = "settings.skipOutro"
        static let autoSelectStream = "settings.autoSelectStream"
        static let requireCachedStreams = "settings.requireCachedStreams"
        static let preferredStreamQuality = "settings.preferredStreamQuality"
        static let subtitleLanguage = "settings.subtitleLanguage"
        static let subtitlesEnabled = "settings.subtitlesEnabled"
        static let traktScrobbling = "settings.traktScrobbling"
        static let builtInPlayer = "settings.builtInPlayer"
        static let preferredExternalPlayer = "settings.preferredExternalPlayer"
        static let useExternalPlayer = "settings.useExternalPlayer"
    }

    // MARK: - Playback

    @Published var resumePlaybackEnabled: Bool {
        didSet { defaults.set(resumePlaybackEnabled, forKey: Key.resumePlayback); CloudSync.shared.setBool(resumePlaybackEnabled, forKey: Key.resumePlayback) }
    }

    @Published var defaultQuality: PlaybackQuality {
        didSet { defaults.set(defaultQuality.rawValue, forKey: Key.defaultQuality); CloudSync.shared.setString(defaultQuality.rawValue, forKey: Key.defaultQuality) }
    }

    /// Which built-in playback engine/profile to use.
    @Published var builtInPlayer: BuiltInPlayer {
        didSet { defaults.set(builtInPlayer.rawValue, forKey: Key.builtInPlayer); CloudSync.shared.setString(builtInPlayer.rawValue, forKey: Key.builtInPlayer) }
    }

    /// Whether to hand playback to an external app instead of playing in-app (iOS).
    @Published var useExternalPlayer: Bool {
        didSet { defaults.set(useExternalPlayer, forKey: Key.useExternalPlayer); CloudSync.shared.setBool(useExternalPlayer, forKey: Key.useExternalPlayer) }
    }

    /// Which external app to hand playback to when `useExternalPlayer` is on.
    @Published var preferredExternalPlayer: ExternalPlayer {
        didSet { defaults.set(preferredExternalPlayer.rawValue, forKey: Key.preferredExternalPlayer); CloudSync.shared.setString(preferredExternalPlayer.rawValue, forKey: Key.preferredExternalPlayer) }
    }

    /// Auto-play the next episode when the current one finishes.
    @Published var autoPlayNext: Bool {
        didSet { defaults.set(autoPlayNext, forKey: Key.autoPlayNext); CloudSync.shared.setBool(autoPlayNext, forKey: Key.autoPlayNext) }
    }

    /// Show a Skip Intro button during the likely intro window.
    @Published var skipIntroEnabled: Bool {
        didSet { defaults.set(skipIntroEnabled, forKey: Key.skipIntro); CloudSync.shared.setBool(skipIntroEnabled, forKey: Key.skipIntro) }
    }

    /// Automatically skip the intro instead of just offering a button.
    @Published var autoSkipIntro: Bool {
        didSet { defaults.set(autoSkipIntro, forKey: Key.autoSkipIntro); CloudSync.shared.setBool(autoSkipIntro, forKey: Key.autoSkipIntro) }
    }

    /// Show a Skip Outro / Next button during the credits.
    @Published var skipOutroEnabled: Bool {
        didSet { defaults.set(skipOutroEnabled, forKey: Key.skipOutro); CloudSync.shared.setBool(skipOutroEnabled, forKey: Key.skipOutro) }
    }

    /// Auto-select the best stream instead of always showing the picker.
    @Published var autoSelectStream: Bool {
        didSet { defaults.set(autoSelectStream, forKey: Key.autoSelectStream); CloudSync.shared.setBool(autoSelectStream, forKey: Key.autoSelectStream) }
    }

    /// Prefer instantly-playable (cached/direct) streams when auto-selecting.
    @Published var requireCachedStreams: Bool {
        didSet { defaults.set(requireCachedStreams, forKey: Key.requireCachedStreams); CloudSync.shared.setBool(requireCachedStreams, forKey: Key.requireCachedStreams) }
    }

    /// Preferred stream resolution for ranking/auto-select.
    @Published var preferredStreamQuality: StreamQuality {
        didSet { defaults.set(preferredStreamQuality.rawValue, forKey: Key.preferredStreamQuality); CloudSync.shared.setString(preferredStreamQuality.rawValue, forKey: Key.preferredStreamQuality) }
    }

    // MARK: - Subtitles

    @Published var subtitlesEnabled: Bool {
        didSet { defaults.set(subtitlesEnabled, forKey: Key.subtitlesEnabled); CloudSync.shared.setBool(subtitlesEnabled, forKey: Key.subtitlesEnabled) }
    }

    /// Preferred subtitle language code (ISO).
    @Published var subtitleLanguage: String {
        didSet { defaults.set(subtitleLanguage, forKey: Key.subtitleLanguage); CloudSync.shared.setString(subtitleLanguage, forKey: Key.subtitleLanguage) }
    }

    // MARK: - Trakt

    @Published var traktScrobblingEnabled: Bool {
        didSet { defaults.set(traktScrobblingEnabled, forKey: Key.traktScrobbling); CloudSync.shared.setBool(traktScrobblingEnabled, forKey: Key.traktScrobbling) }
    }

    // MARK: - Legal / privacy

    @Published var requireLegalConfirmation: Bool {
        didSet { defaults.set(requireLegalConfirmation, forKey: Key.requireLegalConfirmation); CloudSync.shared.setBool(requireLegalConfirmation, forKey: Key.requireLegalConfirmation) }
    }

    // MARK: - First-run

    var didSeedMockData: Bool {
        get { defaults.bool(forKey: Key.didSeedMockData) }
        set { defaults.set(newValue, forKey: Key.didSeedMockData) }
    }

    // MARK: - Init

    init() {
        // Establish defaults the first time only.
        let firstRunDefaults: [String: Any] = [
            Key.resumePlayback: true,
            Key.requireLegalConfirmation: true,
            Key.autoPlayNext: true,
            Key.skipIntro: true,
            Key.autoSkipIntro: false,
            Key.skipOutro: true,
            Key.autoSelectStream: false,
            Key.requireCachedStreams: true,
            Key.subtitlesEnabled: true,
            Key.traktScrobbling: true
        ]
        for (k, v) in firstRunDefaults where defaults.object(forKey: k) == nil {
            defaults.set(v, forKey: k)
        }

        self.resumePlaybackEnabled = defaults.bool(forKey: Key.resumePlayback)
        self.requireLegalConfirmation = defaults.bool(forKey: Key.requireLegalConfirmation)
        self.defaultQuality = PlaybackQuality(
            rawValue: defaults.string(forKey: Key.defaultQuality) ?? PlaybackQuality.auto.rawValue
        ) ?? .auto
        self.autoPlayNext = defaults.bool(forKey: Key.autoPlayNext)
        self.skipIntroEnabled = defaults.bool(forKey: Key.skipIntro)
        self.autoSkipIntro = defaults.bool(forKey: Key.autoSkipIntro)
        self.skipOutroEnabled = defaults.bool(forKey: Key.skipOutro)
        self.autoSelectStream = defaults.bool(forKey: Key.autoSelectStream)
        self.requireCachedStreams = defaults.bool(forKey: Key.requireCachedStreams)
        self.preferredStreamQuality = StreamQuality(
            rawValue: defaults.string(forKey: Key.preferredStreamQuality) ?? StreamQuality.fhd1080.rawValue
        ) ?? .fhd1080
        self.subtitlesEnabled = defaults.bool(forKey: Key.subtitlesEnabled)
        self.subtitleLanguage = defaults.string(forKey: Key.subtitleLanguage) ?? "en"
        self.traktScrobblingEnabled = defaults.bool(forKey: Key.traktScrobbling)
        self.builtInPlayer = BuiltInPlayer(
            rawValue: defaults.string(forKey: Key.builtInPlayer) ?? BuiltInPlayer.auto.rawValue
        ) ?? .auto
        self.useExternalPlayer = defaults.bool(forKey: Key.useExternalPlayer)
        self.preferredExternalPlayer = ExternalPlayer(
            rawValue: defaults.string(forKey: Key.preferredExternalPlayer) ?? ExternalPlayer.infuse.rawValue
        ) ?? .infuse

        // Pull any iCloud values that exist (a newer device may have synced).
        mergeFromCloud()

        // Live updates when another device changes a setting.
        CloudSync.shared.externalChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.mergeFromCloud() }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    /// Applies any values present in iCloud KVS over the local ones. Setting the
    /// @Published properties also re-persists locally via their didSet, keeping
    /// UserDefaults and iCloud consistent. Writes are skipped when unchanged to
    /// avoid feedback loops.
    private func mergeFromCloud() {
        let cloud = CloudSync.shared

        func applyBool(_ kv: String, _ keyPath: ReferenceWritableKeyPath<SettingsStore, Bool>) {
            if let v = cloud.bool(forKey: kv), self[keyPath: keyPath] != v {
                self[keyPath: keyPath] = v
            }
        }
        applyBool(Key.resumePlayback, \.resumePlaybackEnabled)
        applyBool(Key.autoPlayNext, \.autoPlayNext)
        applyBool(Key.skipIntro, \.skipIntroEnabled)
        applyBool(Key.autoSkipIntro, \.autoSkipIntro)
        applyBool(Key.skipOutro, \.skipOutroEnabled)
        applyBool(Key.autoSelectStream, \.autoSelectStream)
        applyBool(Key.requireCachedStreams, \.requireCachedStreams)
        applyBool(Key.subtitlesEnabled, \.subtitlesEnabled)
        applyBool(Key.traktScrobbling, \.traktScrobblingEnabled)
        applyBool(Key.requireLegalConfirmation, \.requireLegalConfirmation)
        applyBool(Key.useExternalPlayer, \.useExternalPlayer)

        if let v = cloud.string(forKey: Key.defaultQuality),
           let q = PlaybackQuality(rawValue: v), defaultQuality != q { defaultQuality = q }
        if let v = cloud.string(forKey: Key.preferredStreamQuality),
           let q = StreamQuality(rawValue: v), preferredStreamQuality != q { preferredStreamQuality = q }
        if let v = cloud.string(forKey: Key.subtitleLanguage), subtitleLanguage != v {
            subtitleLanguage = v
        }
        if let v = cloud.string(forKey: Key.builtInPlayer),
           let p = BuiltInPlayer(rawValue: v), builtInPlayer != p { builtInPlayer = p }
        if let v = cloud.string(forKey: Key.preferredExternalPlayer),
           let p = ExternalPlayer(rawValue: v), preferredExternalPlayer != p { preferredExternalPlayer = p }
    }
}

enum PlaybackQuality: String, CaseIterable, Identifiable {
    case auto
    case high
    case medium
    case low

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto:   return "Auto"
        case .high:   return "High"
        case .medium: return "Medium"
        case .low:    return "Low"
        }
    }
}
