# Astra 1.8 Build 15 — Playback, Player, and Subtitle Update

## Resume playback

- Progress is resolved using the stable media content key when a refreshed stream has a different transient UUID.
- Existing watch position survives stream URL refreshes and library record replacement.
- AVPlayer requests the saved timestamp with zero seek tolerance.
- VLC seeks using its millisecond media clock rather than a normalized fraction.
- Checkpoints are written every five seconds and immediately when playback pauses, the app backgrounds, the player minimizes, or playback stops. Resume becomes available after five seconds of meaningful playback.
- Progress remains resumable after 90%; it is cleared only when playback reaches the actual end.
- A safety path adds playable items to the library before saving progress when a deep link bypasses the normal add flow.

## Apple TV visual system and player redesign

- The default palette is true black, neutral translucent white materials, white typography, and Apple system blue for selection and progress.
- Artwork no longer recolors navigation, focus rings, or playback controls.
- AVPlayer uses the native Apple transport, scrubbing, Picture in Picture, AirPlay, and tvOS contextual actions.
- The iOS AVPlayer surface adds lightweight minimize, subtitle, and stop accessories without creating a second fullscreen presentation.
- VLC defaults to a redesigned Apple TV-style overlay with a large white play/pause control, ten-second skips, timeline, elapsed/remaining time, title metadata, subtitle action, aspect action, diagnostics, and next episode.
- The minimized Now Playing surface uses neutral material, live progress, and Apple-style transport treatment.

## Subtitle automation

- Playback queries every enabled Stremio subtitle add-on when a movie or episode starts, with a per-provider timeout so one unhealthy add-on cannot hold the picker open indefinitely.
- OpenSubtitles results are merged when the user has supplied an API key.
- The preferred language is downloaded and selected automatically when **Auto-Download from Add-ons** is enabled, including two-letter codes, three-letter codes, regional codes, and provider display names.
- Both AVPlayer and VLC subtitle pickers include an explicit **Download from Add-ons** action for an on-demand refresh.
- AVPlayer normalizes provider SRT/VTT files and renders them through a timed-text overlay, avoiding unreliable mutable-composition sideloading.
- VLC downloads provider files, attaches them as enforced subtitle slaves, refreshes the native track list, and supports embedded/provider/off switching.
- iOS retains local subtitle file import; unsupported file-picker APIs remain excluded from tvOS.

## Platform isolation

- iPhone/iPad-only Picture in Picture, status bar, file importer, and navigation toolbar APIs remain behind `#if os(iOS)`.
- tvOS contextual actions, focus sections, remote commands, and transport configuration remain behind `#if os(tvOS)`.
- VLC code remains behind `#if canImport(VLCKitSPM)`.
- Shared subtitle discovery, progress persistence, theme tokens, and media identity logic compile for both app targets.

## Validation

- All active Swift sources pass Swift frontend syntax parsing.
- Every active Swift source is registered in both iOS/iPadOS and tvOS app targets.
- Project and plist structure validation is included in the release checks.
- A complete Apple SDK build still needs to be run in Xcode because the packaging environment does not include Xcode or Apple platform SDKs.
