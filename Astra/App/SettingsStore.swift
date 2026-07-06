//
//  SettingsStore.swift
//  Astra
//
//  Lightweight user-preferences store backed by UserDefaults. Holds non-secret
//  settings only (secrets live in Keychain).
//

import SwiftUI
import Combine

/// How to resolve conflicts when local watch state and Trakt disagree.
enum TraktConflictBehavior: String, CaseIterable, Identifiable {
    case localWins = "Local wins"
    case traktWins = "Trakt wins"
    case ask = "Ask"
    var id: String { rawValue }
}

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
        static let safeMode = "settings.safeMode"
        static let requireCachedStreams = "settings.requireCachedStreams"
        static let preferredStreamQuality = "settings.preferredStreamQuality"
        static let maxStreamSizeGB = "settings.maxStreamSizeGB"
        static let preferredSourceKind = "settings.preferredSourceKind"
        static let minSeeders = "settings.minSeeders"
        static let preferEfficientCodec = "settings.preferEfficientCodec"
        static let preferredAudioLanguage = "settings.preferredAudioLanguage"
        static let subtitleLanguage = "settings.subtitleLanguage"
        static let subtitlesEnabled = "settings.subtitlesEnabled"
        static let playbackSpeed = "settings.playbackSpeed"
        static let nightMode = "settings.nightMode"
        static let bandwidthSaver = "settings.bandwidthSaver"
        static let travelMode = "settings.travelMode"
        static let traktScrobbling = "settings.traktScrobbling"
        static let traktMinWatchPercent = "settings.traktMinWatchPercent"
        static let traktSyncProgress = "settings.traktSyncProgress"
        static let traktSyncFavorites = "settings.traktSyncFavorites"
        static let traktConflict = "settings.traktConflict"
        static let traktLastSync = "settings.traktLastSync"
        static let guestMode = "settings.guestMode"
        static let guestPIN = "settings.guestPIN"
        static let builtInPlayer = "settings.builtInPlayer"
        static let preferredExternalPlayer = "settings.preferredExternalPlayer"
        static let useExternalPlayer = "settings.useExternalPlayer"
        static let searchLayout = "settings.searchLayout"
        static let vlcOverlayStyle = "settings.vlcOverlayStyle"
        static let respectSystemTextSize = "settings.respectSystemTextSize"
        static let textSizeBoost = "settings.textSizeBoost"
        static let homeStyle = "settings.homeStyle"
        static let libraryStyle = "settings.libraryStyle"
        static let libraryColumnCount = "settings.libraryColumnCount"
        static let tabBarStyle = "settings.tabBarStyle"
        static let uiStyle = "settings.uiStyle"
        static let detailStyle = "settings.detailStyle"
        static let reviewSafeMode = "settings.reviewSafeMode"
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

    /// Safe Mode: when on, addons, AI search, and external/network sources are
    /// disabled so the app loads quickly even if a bad addon or source is hanging.
    /// Local-only (not synced) since it's a per-device recovery switch.
    @Published var safeMode: Bool {
        didSet { defaults.set(safeMode, forKey: Key.safeMode) }
    }

    /// Prefer instantly-playable (cached/direct) streams when auto-selecting.
    @Published var requireCachedStreams: Bool {
        didSet { defaults.set(requireCachedStreams, forKey: Key.requireCachedStreams); CloudSync.shared.setBool(requireCachedStreams, forKey: Key.requireCachedStreams) }
    }

    /// Preferred stream resolution for ranking/auto-select.
    @Published var preferredStreamQuality: StreamQuality {
        didSet { defaults.set(preferredStreamQuality.rawValue, forKey: Key.preferredStreamQuality); CloudSync.shared.setString(preferredStreamQuality.rawValue, forKey: Key.preferredStreamQuality) }
    }

    /// Maximum stream size in GB. 0 means no limit. Streams larger than this are
    /// pushed down the list (and excluded from auto-select).
    @Published var maxStreamSizeGB: Int {
        didSet { defaults.set(maxStreamSizeGB, forKey: Key.maxStreamSizeGB); CloudSync.shared.setDouble(Double(maxStreamSizeGB), forKey: Key.maxStreamSizeGB) }
    }

    /// Preferred source kind (Any, Cloud/Debrid, Torrent, Local SMB, Direct). A
    /// matching source is boosted in ranking.
    @Published var preferredSourceKind: SourceKindPreference {
        didSet { defaults.set(preferredSourceKind.rawValue, forKey: Key.preferredSourceKind); CloudSync.shared.setString(preferredSourceKind.rawValue, forKey: Key.preferredSourceKind) }
    }

    /// Minimum seeders for non-cached torrents. Torrents below this are pushed down
    /// (cached sources are unaffected). 0 means no minimum.
    @Published var minSeeders: Int {
        didSet { defaults.set(minSeeders, forKey: Key.minSeeders); CloudSync.shared.setDouble(Double(minSeeders), forKey: Key.minSeeders) }
    }

    /// Prefer efficient codecs (HEVC / AV1) when otherwise similar.
    @Published var preferEfficientCodec: Bool {
        didSet { defaults.set(preferEfficientCodec, forKey: Key.preferEfficientCodec); CloudSync.shared.setBool(preferEfficientCodec, forKey: Key.preferEfficientCodec) }
    }

    /// Preferred audio language tag (e.g. "EN"). Empty means no preference. A stream
    /// offering this language is boosted.
    @Published var preferredAudioLanguage: String {
        didSet { defaults.set(preferredAudioLanguage, forKey: Key.preferredAudioLanguage); CloudSync.shared.setString(preferredAudioLanguage, forKey: Key.preferredAudioLanguage) }
    }

    // MARK: - Subtitles

    @Published var subtitlesEnabled: Bool {
        didSet { defaults.set(subtitlesEnabled, forKey: Key.subtitlesEnabled); CloudSync.shared.setBool(subtitlesEnabled, forKey: Key.subtitlesEnabled) }
    }

    /// Default playback speed (1.0 = normal). Applied by the players.
    @Published var playbackSpeed: Double {
        didSet { defaults.set(playbackSpeed, forKey: Key.playbackSpeed); CloudSync.shared.setDouble(playbackSpeed, forKey: Key.playbackSpeed) }
    }

    // MARK: - Watching modes (Batch D)

    /// Night watching: dim the player overlay and avoid aggressive autoplay.
    @Published var nightMode: Bool {
        didSet { defaults.set(nightMode, forKey: Key.nightMode); CloudSync.shared.setBool(nightMode, forKey: Key.nightMode) }
    }
    /// Bandwidth saver: prefer smaller files, efficient codecs, lower resolution.
    @Published var bandwidthSaver: Bool {
        didSet { defaults.set(bandwidthSaver, forKey: Key.bandwidthSaver); CloudSync.shared.setBool(bandwidthSaver, forKey: Key.bandwidthSaver) }
    }
    /// Travel mode: prefer stable cached/resolved streams and lower default quality.
    @Published var travelMode: Bool {
        didSet { defaults.set(travelMode, forKey: Key.travelMode); CloudSync.shared.setBool(travelMode, forKey: Key.travelMode) }
    }

    /// Preferred subtitle language code (ISO).
    @Published var subtitleLanguage: String {
        didSet { defaults.set(subtitleLanguage, forKey: Key.subtitleLanguage); CloudSync.shared.setString(subtitleLanguage, forKey: Key.subtitleLanguage) }
    }

    // MARK: - Trakt

    @Published var traktScrobblingEnabled: Bool {
        didSet { defaults.set(traktScrobblingEnabled, forKey: Key.traktScrobbling); CloudSync.shared.setBool(traktScrobblingEnabled, forKey: Key.traktScrobbling) }
    }

    /// Minimum watched percentage before a title is marked watched on Trakt.
    @Published var traktMinWatchPercent: Int {
        didSet { defaults.set(traktMinWatchPercent, forKey: Key.traktMinWatchPercent); CloudSync.shared.setDouble(Double(traktMinWatchPercent), forKey: Key.traktMinWatchPercent) }
    }
    @Published var traktSyncProgress: Bool {
        didSet { defaults.set(traktSyncProgress, forKey: Key.traktSyncProgress); CloudSync.shared.setBool(traktSyncProgress, forKey: Key.traktSyncProgress) }
    }
    @Published var traktSyncFavorites: Bool {
        didSet { defaults.set(traktSyncFavorites, forKey: Key.traktSyncFavorites); CloudSync.shared.setBool(traktSyncFavorites, forKey: Key.traktSyncFavorites) }
    }
    /// Conflict resolution when local and Trakt disagree.
    @Published var traktConflict: TraktConflictBehavior {
        didSet { defaults.set(traktConflict.rawValue, forKey: Key.traktConflict); CloudSync.shared.setString(traktConflict.rawValue, forKey: Key.traktConflict) }
    }

    // MARK: - Guest mode

    /// When on, source setup, magnets/direct URLs, and advanced settings are hidden,
    /// so a shared Apple TV shows only the library and playback. A PIN gates exit.
    @Published var guestMode: Bool {
        didSet { defaults.set(guestMode, forKey: Key.guestMode) }
    }
    /// Optional 4-digit PIN required to leave guest mode. Empty = no PIN.
    @Published var guestPIN: String {
        didSet { defaults.set(guestPIN, forKey: Key.guestPIN) }
    }

    // MARK: - Legal / privacy

    @Published var requireLegalConfirmation: Bool {
        didSet { defaults.set(requireLegalConfirmation, forKey: Key.requireLegalConfirmation); CloudSync.shared.setBool(requireLegalConfirmation, forKey: Key.requireLegalConfirmation) }
    }

    // MARK: - Appearance / Interface

    /// How the Home screen is presented: the new cinematic look (default) with a
    /// swipeable hero carousel and painterly Discover tiles, or the classic dashboard.
    @Published var homeStyle: HomeStyle {
        didSet { defaults.set(homeStyle.rawValue, forKey: Key.homeStyle); CloudSync.shared.setString(homeStyle.rawValue, forKey: Key.homeStyle) }
    }

    /// How the library media-detail sheet is presented: the new cinematic glass-card
    /// look (default) with a tile grid of actions, or the classic stacked buttons.
    @Published var detailStyle: DetailStyle {
        didSet { defaults.set(detailStyle.rawValue, forKey: Key.detailStyle); CloudSync.shared.setString(detailStyle.rawValue, forKey: Key.detailStyle) }
    }

    /// How the Library screen is presented: the new clean look (default) with a
    /// segmented All/Movies/Shows control and an options menu, or the classic chips.
    @Published var libraryStyle: LibraryStyle {
        didSet { defaults.set(libraryStyle.rawValue, forKey: Key.libraryStyle); CloudSync.shared.setString(libraryStyle.rawValue, forKey: Key.libraryStyle) }
    }

    /// How many poster columns the library grid shows on iPhone/iPad. Default 3.
    /// Clamped to a sensible range so the grid never looks broken.
    @Published var libraryColumnCount: Int {
        didSet {
            let clamped = min(max(libraryColumnCount, 2), 5)
            if clamped != libraryColumnCount { libraryColumnCount = clamped; return }
            defaults.set(libraryColumnCount, forKey: Key.libraryColumnCount)
            CloudSync.shared.setDouble(Double(libraryColumnCount), forKey: Key.libraryColumnCount)
        }
    }

    /// The iOS tab bar look: the new floating translucent pill (default) or the
    /// standard system tab bar. tvOS is unaffected (it uses a menu overlay).
    @Published var tabBarStyle: TabBarStyle {
        didSet { defaults.set(tabBarStyle.rawValue, forKey: Key.tabBarStyle); CloudSync.shared.setString(tabBarStyle.rawValue, forKey: Key.tabBarStyle) }
    }

    /// The app-wide component look (buttons, cards, rows). Pushes into Theme so the
    /// shared ButtonStyles reflect it immediately.
    @Published var uiStyle: UIComponentStyle {
        didSet {
            defaults.set(uiStyle.rawValue, forKey: Key.uiStyle)
            CloudSync.shared.setString(uiStyle.rawValue, forKey: Key.uiStyle)
            Theme.uiStyle = uiStyle
        }
    }

    /// How search results are laid out: a poster grid, or Apple-TV-style horizontal
    /// rails grouped by kind (Movies / TV Shows). Both remain fully usable.
    @Published var searchLayout: SearchLayoutStyle {
        didSet { defaults.set(searchLayout.rawValue, forKey: Key.searchLayout); CloudSync.shared.setString(searchLayout.rawValue, forKey: Key.searchLayout) }
    }

    /// The VLC player's on-screen overlay: the classic centered transport, or a
    /// native-style bar (left-aligned title, thin scrubber, text control row) that
    /// matches Apple's player. AVPlayer always uses Apple's own native overlay.
    @Published var vlcOverlayStyle: PlayerOverlayStyle {
        didSet { defaults.set(vlcOverlayStyle.rawValue, forKey: Key.vlcOverlayStyle); CloudSync.shared.setString(vlcOverlayStyle.rawValue, forKey: Key.vlcOverlayStyle) }
    }

    // MARK: - Accessibility / Text size

    /// When on (default), app text scales with the system Dynamic Type / Larger Text
    /// setting on iOS. When off, text stays at the app's designed size. tvOS ignores
    /// this (no Dynamic Type). Pushes the value into Theme so `appFont` reflects it.
    @Published var respectSystemTextSize: Bool {
        didSet {
            defaults.set(respectSystemTextSize, forKey: Key.respectSystemTextSize)
            CloudSync.shared.setBool(respectSystemTextSize, forKey: Key.respectSystemTextSize)
            applyTextSizeToTheme()
        }
    }

    /// An in-app text-size multiplier (1.0 = normal) so users can enlarge Astra's
    /// text without changing their whole device. Clamped to a sensible range.
    @Published var textSizeBoost: Double {
        didSet {
            defaults.set(textSizeBoost, forKey: Key.textSizeBoost)
            CloudSync.shared.setDouble(textSizeBoost, forKey: Key.textSizeBoost)
            applyTextSizeToTheme()
        }
    }

    /// When on, the app hides the Real-Debrid, magnet, and addon stream-resolution
    /// surfaces, leaving direct URLs, SMB, Trakt, and the library intact. This is the
    /// groundwork for an App Store review-safe configuration. Deliberately NOT synced
    /// to iCloud so it can be set per device.
    @Published var reviewSafeMode: Bool {
        didSet { defaults.set(reviewSafeMode, forKey: Key.reviewSafeMode) }
    }

    /// Mirrors the current text-size preferences into Theme's static fields, which
    /// `appFont` reads. Called on init and whenever either preference changes.
    private func applyTextSizeToTheme() {
        #if os(iOS)
        Theme.respectSystemTextSize = respectSystemTextSize
        Theme.textSizeBoost = CGFloat(textSizeBoost)
        #endif
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
            Key.traktScrobbling: true,
            Key.respectSystemTextSize: true,
            Key.textSizeBoost: 1.0
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
        self.safeMode = defaults.bool(forKey: Key.safeMode)
        self.requireCachedStreams = defaults.bool(forKey: Key.requireCachedStreams)
        self.preferredStreamQuality = StreamQuality(
            rawValue: defaults.string(forKey: Key.preferredStreamQuality) ?? StreamQuality.fhd1080.rawValue
        ) ?? .fhd1080
        self.maxStreamSizeGB = defaults.integer(forKey: Key.maxStreamSizeGB)   // 0 = no limit
        self.preferredSourceKind = SourceKindPreference(
            rawValue: defaults.string(forKey: Key.preferredSourceKind) ?? SourceKindPreference.any.rawValue
        ) ?? .any
        self.minSeeders = defaults.integer(forKey: Key.minSeeders)             // 0 = no minimum
        self.preferEfficientCodec = defaults.bool(forKey: Key.preferEfficientCodec)
        self.preferredAudioLanguage = defaults.string(forKey: Key.preferredAudioLanguage) ?? ""
        self.subtitlesEnabled = defaults.bool(forKey: Key.subtitlesEnabled)
        // Playback speed defaults to 1.0 (UserDefaults returns 0 when unset).
        let savedSpeed = defaults.double(forKey: Key.playbackSpeed)
        self.playbackSpeed = savedSpeed > 0 ? savedSpeed : 1.0
        self.nightMode = defaults.bool(forKey: Key.nightMode)
        self.bandwidthSaver = defaults.bool(forKey: Key.bandwidthSaver)
        self.travelMode = defaults.bool(forKey: Key.travelMode)
        self.subtitleLanguage = defaults.string(forKey: Key.subtitleLanguage) ?? "en"
        self.traktScrobblingEnabled = defaults.bool(forKey: Key.traktScrobbling)
        let savedTraktMinWatch = defaults.integer(forKey: Key.traktMinWatchPercent)
        self.traktMinWatchPercent = savedTraktMinWatch == 0 ? 90 : savedTraktMinWatch   // default 90% if unset
        self.traktSyncProgress = defaults.object(forKey: Key.traktSyncProgress) == nil ? true : defaults.bool(forKey: Key.traktSyncProgress)
        self.traktSyncFavorites = defaults.object(forKey: Key.traktSyncFavorites) == nil ? true : defaults.bool(forKey: Key.traktSyncFavorites)
        self.traktConflict = TraktConflictBehavior(rawValue: defaults.string(forKey: Key.traktConflict) ?? "") ?? .ask
        self.guestMode = defaults.bool(forKey: Key.guestMode)
        self.guestPIN = defaults.string(forKey: Key.guestPIN) ?? ""
        self.builtInPlayer = BuiltInPlayer(
            rawValue: defaults.string(forKey: Key.builtInPlayer) ?? BuiltInPlayer.auto.rawValue
        ) ?? .auto
        self.useExternalPlayer = defaults.bool(forKey: Key.useExternalPlayer)
        self.preferredExternalPlayer = ExternalPlayer(
            rawValue: defaults.string(forKey: Key.preferredExternalPlayer) ?? ExternalPlayer.infuse.rawValue
        ) ?? .infuse
        self.searchLayout = SearchLayoutStyle(
            rawValue: defaults.string(forKey: Key.searchLayout) ?? SearchLayoutStyle.grid.rawValue
        ) ?? .grid
        self.homeStyle = HomeStyle(
            rawValue: defaults.string(forKey: Key.homeStyle) ?? HomeStyle.cinematic.rawValue
        ) ?? .cinematic
        let storedCols = defaults.object(forKey: Key.libraryColumnCount) as? Int
        self.libraryColumnCount = storedCols.map { min(max($0, 2), 5) } ?? 3
        self.libraryStyle = LibraryStyle(
            rawValue: defaults.string(forKey: Key.libraryStyle) ?? LibraryStyle.clean.rawValue
        ) ?? .clean
        self.detailStyle = DetailStyle(
            rawValue: defaults.string(forKey: Key.detailStyle) ?? DetailStyle.cinematic.rawValue
        ) ?? .cinematic
        self.reviewSafeMode = defaults.bool(forKey: Key.reviewSafeMode)
        self.tabBarStyle = TabBarStyle(
            rawValue: defaults.string(forKey: Key.tabBarStyle) ?? TabBarStyle.floatingPill.rawValue
        ) ?? .floatingPill
        let resolvedUIStyle = UIComponentStyle(
            rawValue: defaults.string(forKey: Key.uiStyle) ?? UIComponentStyle.refined.rawValue
        ) ?? .refined
        self.uiStyle = resolvedUIStyle
        Theme.uiStyle = resolvedUIStyle
        self.vlcOverlayStyle = PlayerOverlayStyle(
            rawValue: defaults.string(forKey: Key.vlcOverlayStyle) ?? PlayerOverlayStyle.classic.rawValue
        ) ?? .classic
        let resolvedRespect = defaults.object(forKey: Key.respectSystemTextSize) == nil
            ? true : defaults.bool(forKey: Key.respectSystemTextSize)
        self.respectSystemTextSize = resolvedRespect
        let savedBoost = defaults.double(forKey: Key.textSizeBoost)
        let resolvedBoost = savedBoost > 0 ? savedBoost : 1.0
        self.textSizeBoost = resolvedBoost

        // Reflect text-size prefs into Theme before any view builds a font. Uses the
        // resolved locals so this doesn't touch `self` before initialization finishes.
        #if os(iOS)
        Theme.respectSystemTextSize = resolvedRespect
        Theme.textSizeBoost = CGFloat(resolvedBoost)
        #endif

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

        applyBool(Key.preferEfficientCodec, \.preferEfficientCodec)
        if let v = cloud.double(forKey: Key.maxStreamSizeGB), maxStreamSizeGB != Int(v) {
            maxStreamSizeGB = Int(v)
        }
        if let v = cloud.double(forKey: Key.minSeeders), minSeeders != Int(v) {
            minSeeders = Int(v)
        }
        if let v = cloud.string(forKey: Key.preferredSourceKind),
           let p = SourceKindPreference(rawValue: v), preferredSourceKind != p { preferredSourceKind = p }
        if let v = cloud.string(forKey: Key.preferredAudioLanguage), preferredAudioLanguage != v {
            preferredAudioLanguage = v
        }
        if let v = cloud.string(forKey: Key.searchLayout),
           let s = SearchLayoutStyle(rawValue: v), searchLayout != s { searchLayout = s }
        if let v = cloud.string(forKey: Key.homeStyle),
           let s = HomeStyle(rawValue: v), homeStyle != s { homeStyle = s }
        if let cloudCols = cloud.double(forKey: Key.libraryColumnCount),
           cloudCols >= 2, Int(cloudCols) != libraryColumnCount {
            libraryColumnCount = Int(cloudCols)
        }
        if let v = cloud.string(forKey: Key.libraryStyle),
           let s = LibraryStyle(rawValue: v), libraryStyle != s { libraryStyle = s }
        if let v = cloud.string(forKey: Key.detailStyle),
           let s = DetailStyle(rawValue: v), detailStyle != s { detailStyle = s }
        if let v = cloud.string(forKey: Key.tabBarStyle),
           let s = TabBarStyle(rawValue: v), tabBarStyle != s { tabBarStyle = s }
        if let v = cloud.string(forKey: Key.uiStyle),
           let s = UIComponentStyle(rawValue: v), uiStyle != s { uiStyle = s }
        if let v = cloud.string(forKey: Key.vlcOverlayStyle),
           let s = PlayerOverlayStyle(rawValue: v), vlcOverlayStyle != s { vlcOverlayStyle = s }
        applyBool(Key.respectSystemTextSize, \.respectSystemTextSize)
        if let v = cloud.double(forKey: Key.textSizeBoost), v > 0, textSizeBoost != v {
            textSizeBoost = v
        }
    }

    /// Builds the ranking preferences bundle from the current streaming settings,
    /// for use by StreamRanker.
    var streamPreferences: StreamRanker.StreamPreferences {
        var prefs = StreamRanker.StreamPreferences(
            preferredQuality: preferredStreamQuality == .unknown ? nil : preferredStreamQuality,
            preferredLanguage: preferredAudioLanguage.isEmpty ? nil : preferredAudioLanguage,
            maxSizeGB: maxStreamSizeGB,
            preferredSource: preferredSourceKind.sourceKind,
            minSeeders: minSeeders,
            preferEfficientCodec: preferEfficientCodec
        )
        // Bandwidth saver tightens toward smaller, efficient streams.
        if bandwidthSaver {
            prefs.preferEfficientCodec = true
            // Cap size to 4 GB unless the user already set a smaller cap.
            prefs.maxSizeGB = prefs.maxSizeGB == 0 ? 4 : min(prefs.maxSizeGB, 4)
            // Prefer 720p when no explicit lower target is set.
            if prefs.preferredQuality == nil || (prefs.preferredQuality?.rank ?? 0) > StreamQuality.hd720.rank {
                prefs.preferredQuality = .hd720
            }
        }
        // Travel mode favors stable, lighter streams off home Wi-Fi.
        if travelMode {
            prefs.preferEfficientCodec = true
            prefs.maxSizeGB = prefs.maxSizeGB == 0 ? 3 : min(prefs.maxSizeGB, 3)
            if prefs.preferredQuality == nil || (prefs.preferredQuality?.rank ?? 0) > StreamQuality.hd720.rank {
                prefs.preferredQuality = .hd720
            }
        }
        return prefs
    }
}

/// User-facing source preference. Maps to SourceKind, with an "Any" option.
enum SourceKindPreference: String, CaseIterable, Identifiable {
    case any
    case cloud        // debrid / direct cloud
    case torrent
    case localSMB
    case directURL

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .any:       return "Any Source"
        case .cloud:     return "Cloud / Debrid"
        case .torrent:   return "Torrent"
        case .localSMB:  return "Local SMB"
        case .directURL: return "Direct URL"
        }
    }

    var systemImage: String {
        switch self {
        case .any:       return "square.stack.3d.up"
        case .cloud:     return "cloud"
        case .torrent:   return "arrow.down.circle"
        case .localSMB:  return "externaldrive.connected.to.line.below"
        case .directURL: return "link"
        }
    }

    /// The matching SourceKind, or nil for "Any".
    var sourceKind: SourceKind? {
        switch self {
        case .any:       return nil
        case .cloud:     return .cloud
        case .torrent:   return .torrent
        case .localSMB:  return .localSMB
        case .directURL: return .directURL
        }
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

// MARK: - Interface style options

/// How the Discover/search results are presented.
enum SearchLayoutStyle: String, CaseIterable, Identifiable {
    /// A responsive poster grid (the original layout).
    case grid
    /// Apple-TV-style horizontal rails, grouped by kind (Movies / TV Shows).
    case rails

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .grid:  return "Grid"
        case .rails: return "Rails"
        }
    }

    var systemImage: String {
        switch self {
        case .grid:  return "square.grid.2x2"
        case .rails: return "rectangle.grid.1x2"
        }
    }
}

/// The visual style of the in-app VLC player overlay.
enum PlayerOverlayStyle: String, CaseIterable, Identifiable {
    /// Centered transport with big round buttons (the original overlay).
    case classic
    /// Apple-style bar: left-aligned title, a thin scrubber with elapsed/remaining
    /// timestamps, and a compact text button row — matching the native player.
    case native

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .native:  return "Native"
        }
    }

    var systemImage: String {
        switch self {
        case .classic: return "play.circle"
        case .native:  return "text.line.first.and.arrowtriangle.forward"
        }
    }
}

/// How the Home screen is presented.
enum HomeStyle: String, CaseIterable, Identifiable {
    /// New default: full-bleed swipeable hero carousel, Continue Watching with
    /// overlay cards, and painterly Discover tiles.
    case cinematic
    /// The classic dashboard: single featured hero, then stacked shelves.
    case classic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cinematic: return "Cinematic"
        case .classic:   return "Classic"
        }
    }
}

/// How the Library screen is presented.
enum LibraryStyle: String, CaseIterable, Identifiable {
    /// New default: a segmented All/Movies/Shows control, a single options menu
    /// (sort, collections, edit, hidden), then a clean poster grid.
    case clean
    /// The classic layout: stacked filter chips and inline header actions.
    case classic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .clean:   return "Clean"
        case .classic: return "Classic"
        }
    }
}

/// The iOS tab bar presentation.
enum TabBarStyle: String, CaseIterable, Identifiable {
    /// New default: a floating translucent pill above the content.
    case floatingPill
    /// The standard system bottom tab bar.
    case system

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .floatingPill: return "Floating Pill"
        case .system:       return "System"
        }
    }
}



/// How the library media-detail sheet is presented.
enum DetailStyle: String, CaseIterable, Identifiable {
    /// New default: frosted glass card over the backdrop, tile grid of actions,
    /// and a destructive Remove row.
    case cinematic
    /// The classic stacked-buttons layout.
    case classic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cinematic: return "Cinematic"
        case .classic:   return "Classic"
        }
    }
}
