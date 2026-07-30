# Astra — 70 Additions, Changes & Fixes

47 source files modified. Split: 22 code fixes (incl. fullscreen), 18 UI, 16 UX, 14 polish.
All changes apply across iOS, iPadOS, and tvOS unless a platform is noted.
`modified/` holds the new files (already written into your Astra folder), `originals/` holds the pre-change copies for easy revert, and `full-diff.patch` is the complete unified diff.

> Note: this environment has no iOS toolchain, so changes were reviewed for correctness (including an adversarial compile/regression review pass) but not compiled. Build in Xcode before shipping.

## Fullscreen playback (1–4)

1. **All 10 player launch points now present as full-screen covers** instead of navigation pushes — Home, Library, Collections, AI, Magnet, Live TV, Direct URL, SMB Browse, Real-Debrid, and the Stream Picker. Nothing else (tab bar, iPad sidebar, mini Now Playing bar) can remain visible while a video plays. *(HomeView, LibraryView, CollectionsView, AIView, MagnetView, LiveTVView, DirectURLView, SMBBrowseView, RealDebridView, StreamPickerView)*
2. **Players get their own NavigationStack inside the cover** (including the RootView "reopen from mini-bar" cover), so next-episode auto-play navigation keeps working. *(RootView + all sites above)*
3. **Home indicator dimmed during playback** via `.persistentSystemOverlays(.hidden)` in both the AVPlayer and VLC players (iOS/iPadOS). *(PlayerView, VLCPlayerView)*
4. **Screen stays awake during playback** — idle timer disabled on player appear, restored on disappear, in both engines (iOS/iPadOS). *(PlayerView, VLCPlayerView)*

## Code fixes (5–22)

5. **LiveTVSourceStore** — the `networkRestored` NotificationCenter observer was re-registered on every `mergeFromCloud()` (init, reload, every iCloud change), leaking observers and firing N redundant refreshes; it now registers exactly once in `init()`.
6. **LiveTVSourceStore** — `seedBuiltInsIfNeeded()` now persists and pushes to iCloud only when a built-in was actually added, instead of re-pushing identical data on every launch.
7. **LiveTVSourceStore** — a source's stale `lastError` is cleared after a successful playlist load, so the failure banner disappears once the source recovers.
8. **EPGService** — re-parsed guides replaced programme lists instead of appending, preventing unbounded duplicate guide entries after every TTL refresh.
9. **SMBStreamServer** — HTTP suffix ranges (`bytes=-N`) were served from the start of the file; now correctly served from the tail, fixing AVPlayer's moov-atom probes over the SMB bridge.
10. **SMBStreamServer** — plain GETs (no Range header) were answered `206` with a bogus Content-Range; now `200 OK`, with `206` only for real range requests.
11. **RealDebridClient** — the intended 30s timeout was set on a copy of `session.configuration` (a no-op); the timeout is now applied per-request.
12. **TMDBClient** — the air-date `DateFormatter` was re-created for every episode of every season; now a cached static (hot-path allocation fix).
13. **RealDebridModels** — `expirationDate` no longer allocates a fresh `ISO8601DateFormatter` on every access.
14. **BackupManager** — three per-call `ISO8601DateFormatter()` allocations consolidated into one shared static.
15. **DirectURLService** — servers that reject HEAD (405/501) are no longer misreported as unreachable.
16. **MetadataParser** — the `1x02` season/episode regex gained word boundaries so `1920x1080` in filenames is no longer parsed as S20 E108.
17. **LibraryStore** — identical iCloud payloads no longer republish the whole library and rewrite the local file on every KVS notification.
18. **LibraryEnricher** — AI title cleanup was the only Worker call missing auth headers, so token-protected Workers rejected it; headers now attached.
19. **AddonStore** — an empty iCloud addon list (e.g. from a fresh device) can no longer wipe every locally installed addon.
20. **StreamRanker** — the seeders regex matched the "S01" in every `S01E02` tag, wrongly triggering "Avoid — Low Seeders"; the bare-S form now requires a colon.
21. **NowPlayingStore** — non-finite progress values (NaN from position/duration math) are guarded so the mini-bar progress line can't render broken.
22. **SettingsStore** — pinned Library collections were pushed to iCloud but never merged back; they now actually sync across devices.

## UI (23–40)

23. **HomeView** — the icon-only hero customize button gained an accessibility label and hint.
24. **HomeView** — decorative hero page-indicator dots hidden from VoiceOver.
25. **HomeView** — Up Next queue rows read as one combined VoiceOver element (poster + title + status).
26. **AIView** — "Clear prompt" accessibility label on the icon-only clear button.
27. **AIView** — suggestion chips use the shared chip button style for a proper tvOS focus/press effect.
28. **DiscoverView** — accessibility labels on the icon-only "Clear search" / "AI search" buttons.
29. **DiscoverView** — empty-shelves hint raised from low-contrast tertiary text to readable secondary.
30. **UniversalSearchView** — same search-field accessibility labels as Discover.
31. **PersonView** — bare `ProgressView` replaced with the app's shared `LoadingView` for consistency.
32. **PersonView** — filmography cards read as one combined VoiceOver element.
33. **MediaCard** — `CatalogPosterCard` gained a full-card tap target (`contentShape`) plus combined accessibility element.
34. **CatalogShelfRow** — magic `white.opacity(0.08)` chip background replaced with the `Theme.Colors.card` token.
35. **SourceCard** — speaks as a single "title, status" button to VoiceOver.
36. **FeaturedHero** — hero backdrop placeholder shimmers instead of popping in from a flat gray box.
37. **StreamPickerView** — filter chips use Theme card color + the shared chip style, gaining the tvOS focus effect.
38. **StreamPickerView** — "Clear smart filter" accessibility label on the icon-only clear button.
39. **AddonsView** — the labels-hidden enable Toggle is now named for VoiceOver.
40. **ContentDetailView** — the circular watched toggle announces "Mark as watched"/"Mark as unwatched" by state.

## UX (41–56)

41. **LiveTVSourcesView** — deleting a custom playlist now asks for confirmation (destructive alert).
42. **LiveTVSourcesView** — "Playlist added" toast when a new M3U/Xtream playlist is saved.
43. **SMBListView** — deleting a saved SMB share (and its Keychain password) now asks for confirmation.
44. **LibraryFoldersView** — removing a scanned folder asks for confirmation and clarifies imported items stay.
45. **RealDebridView** — "Remove Real-Debrid Token?" destructive confirmation before sign-out.
46. **TraktConnectView** — "Disconnect Trakt?" destructive confirmation before sign-out.
47. **TraktConnectView** — "Trakt sync complete" toast after the manual Sync Now.
48. **AccountsView** — Save Credentials is disabled and dimmed while all fields are empty.
49. **AccountsView** — "Credentials saved" toast on save.
50. **DirectURLView** — URL fields use the URL keyboard with autocapitalization/autocorrection off (iOS/iPadOS).
51. **DirectURLView** — "Added … to your library" toast after Add to Library.
52. **MagnetView** — keyboard return submits the magnet link when valid.
53. **DuplicatesView** — merge-result toasts for both Merge All and per-group merges.
54. **TitleCleanupRulesView** — Reset to Defaults asks for confirmation before discarding custom rules.
55. **LiveTVView** — pull-to-refresh on the channel list reloads playlists and the EPG (iOS/iPadOS).
56. **SMBBrowseView** — "Added … to your library" toast when a single video's Add succeeds.

## Polish (57–70)

57. **Theme** — new reusable `Theme.Motion.spring` animation constant (additive).
58. **RootView** — the mini Now Playing bar springs in/out instead of snapping.
59. **RootView** — the "% complete" digits roll with `.numericText()` instead of hard-swapping.
60. **RootView** — the mini-bar progress capsule glides to new widths.
61. **RootView** — light impact haptic on the mini-bar resume button (iOS/iPadOS).
62. **PlayerView** — the Resume/Restart prompt enters with a springy scale + fade.
63. **PlayerView** — light impact haptic on "Resume from …" (iOS/iPadOS).
64. **PlayerView** — the Night Mode veil fades in/out instead of snapping.
65. **PlayerView** — subtitle picker sheet gets medium/large detents and a drag indicator (iOS/iPadOS).
66. **VLCPlayerView** — Audio & Subtitles sheet gets the same detents + drag indicator (iOS/iPadOS).
67. **VLCPlayerView** — light impact haptic on play/pause in both control overlays (iOS/iPadOS).
68. **VLCPlayerView** — the Resume/Start Over prompt gets the same springy entrance.
69. **TVMenuOverlay** — tab pills compress slightly while the remote click is held (tvOS).
70. **SubtitlePickerView** — success haptic when a subtitle track (or Off) is applied (iOS/iPadOS).
