# Omni 1.7 (279) for tvOS: teardown

Source: `Omni-1.7-279-tvos.ipa`. This is static analysis only: bundle contents, Info.plist, linked libraries, binary strings and Swift type names. Nothing was run or decrypted, and no network traffic was captured.

## Identity

| | |
|---|---|
| Bundle ID | `win.stkc.omni` (the developer goes by "stekc"; their domain is stkc.win) |
| Platform | tvOS 18.0 and later, arm64. Built with Xcode 27.1 against the tvOS 27.0 SDK |
| URL scheme | `omni://`, including `x-callback-url` returns from external players and `omni://trakt-bridge/manifest.json` |
| Size | 53 MB unpacked. The main binary is 48 MB because FFmpeg, mpv, libplacebo and other libraries are linked in statically |
| Extensions | `OmniTopShelf.appex` (Top Shelf content provider, `OmniTopShelf.ContentProvider`) |
| Background modes | `audio`, `remote-notification` |
| ATS exception | Plain HTTP is allowed to `*.amazonaws.com` |

## What it is

Omni is a **native SwiftUI Apple TV client for the Stremio addon protocol**. It ships no content of its own. The user installs addon URLs, and the app calls each addon's `manifest.json` and its `catalog`, `meta`, `stream` and `subtitles` resources. It then lays the results out as Netflix-style shelves, with TMDB artwork, Trakt sync and its own player stack.

Evidence: the types `StremioAddon`, `StremioAddonCatalog`, `StremioStream`, `StreamBehaviorHints`, `ProxyHeaders` and `StremioStreamResponse`, the manifest fields `idPrefixes`, `resources` and `behaviorHints`, and messages like "No suitable addon found for content type".

## Architecture (from leaked source paths)

The debug paths under `/Users/me/Developer/Omni/` show the project layout:

```
Omni/TVCatalogApp.swift              ← @main App
Omni/Services/
  StremioAddonService                ← addon HTTP client (manifest/catalog/meta/stream)
  StremioAddonStorageService         ← persists installed addons (SwiftData + iCloud)
  TMDBService                        ← api.themoviedb.org/3 (discover, artwork)
  TraktService / TraktBridgeService  ← api.trakt.tv OAuth device flow + sync; exposes Trakt as a virtual addon
  WatchHistoryService, FavoriteService, BackupService, SettingsManager
  WebServerService                   ← embedded HTTP server for phone/browser management
  TVRemotePlaybackService            ← iPhone/iPad remote control (DeviceDiscoveryUI)
  StrmAPIService                     ← strmapi.stkc.win, makes .strm handoffs for Infuse
  ExternalPlayerTrackingService, ExternalPlaybackDurationProbeService
  SecurityManager                    ← jailbreak detection
Omni/Views/
  FeaturedHeroView, TopRowCatalogShelf, StremioCatalogShelf, StremioLiveTVShelf,
  ContinueWatchingShelf, TrailerShelf, AIShelf, CustomSidebar, GroupCatalogView,
  TitleView, StreamsView, SearchView, MyLibraryView, SettingsView,
  KSPlayerView, AVPlayerView, CachedAsyncImage
Omni/Utilities/ ColorExtractor, ImageCropper, MediaIdNormalizer
```

Other services found by type name only: `MDBListService`, `HomeKitAmbientService`, `GoveeLANService`, `ShazamService`, `SubtitleManager`, `CacheService`, `HeroCache`, `ContinueWatchingCacheService`/`Resolver`, `SearchHistoryService`, `AdaptiveBufferManager`, `AtmosPlaybackCoordinator`, `HLSAtmosServer`, `AudioStreamServer` and `OmniPlayerEngine`. There's also a separate `OmniKit` module.

**Persistence:** SwiftData models (`WatchHistoryItem`, `FavoriteEntry`, `StreamHistoryItem`, `OrderedCatalog`, `OrderedRegexPattern`, `ServerPreference`, `SidebarItemsPreference`, …) synced through CloudKit/iCloud. Settings strings say "Delete … from device and iCloud".

## Feature map

- **Home:** a hero banner, then shelves built from addon catalogs. Users can rename, reorder, pin, star and group catalogs. Also Continue Watching, a trailer shelf (YouTube oEmbed and thumbnails), Live TV shelves, and an **AI shelf/search** that queries "AI search addons".
- **Stream picking with regex rules:** users define regex patterns, each with a color, an image tag, a tag and an auto-play toggle. The patterns are matched against stream names to label results by quality or source and to pick one for auto-play. For example, `(?i)(DOLBY\s*ATMOS|TRUEHD(?:\s*[257]\.1)?)`. Patterns can be imported from a URL or exported.
- **Players:**
  - **KSPlayer** with an **mpv** backend (libmpv 0.41, libplacebo, dav1d, libdovi for Dolby Vision, libass for subtitles)
  - **AVKit** native player
  - External handoff to **Infuse**, SenPlayer, VidHub and MoonPlayer through x-callback URLs, with failure callbacks back to `omni://`
- **Dolby Atmos:** remuxes TrueHD or E-AC3 to HLS through a local server (`HLSAtmosServer`, "HLS Remux (Atmos)") so AVPlayer can output spatial audio.
- **Subtitles:** from addons and from OpenSubtitles (`api.opensubtitles.com`), with preferred-language matching.
- **Metadata and ratings:** TMDB, plus MDBList rating badges (API key set by the user, with configurable sources, colors and order).
- **Trakt:** OAuth device-code flow (`/oauth/device/code`, `/oauth/device/token`). Syncs watched items, collection, watchlist, favorites, playback progress, `up_next_nitro`, recommendations and calendar. Also exposed as a virtual addon (`trakt://omni/manifest.json`).
- **Ambient lighting:** HomeKit lights and Govee lights over the LAN take colors from video frames, the hero banner and title backdrops (`ColorExtractor`).
- **Shazam:** identifies music playing in the current video.
- **Remote control:** iPhone/iPad companion through `NSApplicationServices` "omni-remote" and DeviceDiscoveryUI, with local-network discovery.
- **Top Shelf** extension.

## Embedded web server (phone/browser management)

`WebServerService` serves the bundled HTML pages: `main`, `install`, `catalogs`, `regex`, `settings`, `backup` and `error`. The TV presumably shows a QR code or URL to open them. Every page polls `GET /server-status`. All mutating calls are `POST`:

| Area | Routes |
|---|---|
| Addons | `/add`, `/addons/uninstall` |
| Catalogs | `/catalogs/rename`, `toggle_enabled`, `toggle_pin`, `toggle_star`, `update_order`, `up`, `down` |
| Regex | `/regex/update_order`, `toggle_tag`, `toggle_auto_play`, `cycle_color`, `cycle_image_color`, `update_color_hex`, `update_image`, `color_get`, `import-from-url`, `preview-from-url`, `export` |
| Settings | `/settings/update` |
| Backup | multipart import ("Missing boundary in import request") with a file version check |

I found no auth token in the page JavaScript, so anyone on the local network can likely reach these endpoints. Verify that at runtime before relying on it.

## External hosts contacted

| Host | Purpose |
|---|---|
| `api.themoviedb.org`, `image.tmdb.org` | Metadata and artwork |
| `api.trakt.tv` | Sync and auth |
| `api.mdblist.com` | Ratings |
| `api.opensubtitles.com/api` | Subtitles |
| `www.youtube.com/oembed`, `img.youtube.com` | Trailers |
| `itunes.apple.com/search` | Probably artwork or music lookup |
| `strmapi.stkc.win` | Developer's own service: generates STRM files for Infuse handoff (`StrmRequest`/`StrmResponse`) |
| `api.makedie.me` | Unknown, only one plain-HTTP reference. Needs runtime tracing |
| `gist.githubusercontent.com/stekc/...` | Open-source license texts |
| User-installed addon URLs | All content and streams |

## Protections

`SecurityManager` checks for jailbreaks: rootless paths (`/var/jb/...`, `MobileSubstrate`, `sudo`), the `PALERA1N_ROOTFUL` and `DYLD_INSERT_LIBRARIES` environment variables, and test writes to `/var/jb/test.txt` and `/var/mobile/test.txt`. What the app does when one is detected wasn't determined statically. The binary is stripped (147 exported symbols), but the Swift type metadata and source paths are intact.

## Third-party components

KSPlayer (LGPL), FFmpegKit, libmpv, libplacebo, shaderc, dav1d, libdovi, libass, harfbuzz, fribidi, freetype, fontconfig, lcms2, opus, SRT, zvbi, OpenSSL, Pow (SwiftUI effects) and Glur (blur).

## Open questions or next steps

1. Disassemble `WebServerService` to get its port, auth handling and request handlers (use REA/Hopper on `_TtC4Omni16WebServerService`).
2. Find out what `api.makedie.me` is used for.
3. Work out the request and response shape of `StrmAPIService`: what stream data gets sent to strmapi.stkc.win.
4. Find out what `SecurityManager` does after a positive check.
5. Trace how regex scoring decides auto-play.
