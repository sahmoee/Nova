# Astra Platform Parity Matrix

Every user-facing capability and where it is supported. Keep this current when
adding features — it is the contract for "does X work on Y."

Legend: ✅ supported · ➖ not applicable · ⚠️ partial / see note · ❌ not yet

| Feature | iPhone | iPad | Apple TV | Widgets | Top Shelf | External players | Background |
|---|---|---|---|---|---|---|---|
| Home shelves & Continue Watching | ✅ | ✅ | ✅ | ⚠️¹ | ⚠️¹ | ➖ | ➖ |
| Universal search (TMDB + predictive + AI) | ✅ | ✅ | ✅ | ➖ | ➖ | ➖ | ➖ |
| Content detail (overview, cast, trailers) | ✅ | ✅ | ✅ | ➖ | ➖ | ➖ | ➖ |
| Stream picker (ranking, "used X ago") | ✅ | ✅ | ✅ | ➖ | ➖ | ➖ | ➖ |
| Playback — AVPlayer engine | ✅ | ✅ | ✅ | ➖ | ➖ | ➖ | ⚠️² |
| Playback — VLC engine | ✅ | ✅ | ✅ | ➖ | ➖ | ➖ | ⚠️² |
| Seamless resume (same stream/position) | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ➖ |
| Now Playing / resume bar | ✅ | ✅ | ✅ | ➖ | ➖ | ➖ | ➖ |
| External player hand-off (Infuse, VLC, etc.) | ✅ | ✅ | ⚠️³ | ➖ | ➖ | ✅ | ➖ |
| Sources: SMB | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ➖ |
| Sources: Live TV (M3U/Xtream) | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ➖ |
| Sources: Add-ons (Stremio-style) | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ➖ |
| Real-Debrid cloud streams | ✅ | ✅ | ✅ | ➖ | ➖ | ✅ | ➖ |
| Trakt sync (watchlist, scrobble) | ✅ | ✅ | ✅ | ➖ | ➖ | ➖ | ⚠️² |
| Library, collections, smart collections | ✅ | ✅ | ✅ | ⚠️¹ | ⚠️¹ | ➖ | ➖ |
| Backup / restore (iCloud + file) | ✅ | ✅ | ✅ | ➖ | ➖ | ➖ | ➖ |
| Share via code (encrypted, one-time) | ✅ | ✅ | ✅ | ➖ | ➖ | ➖ | ➖ |
| Settings + guided setup + Settings search | ✅ | ✅ | ✅ | ➖ | ➖ | ➖ | ➖ |
| Recommendation feedback (More Like This) | ✅ | ✅ | ✅ | ➖ | ➖ | ➖ | ➖ |
| Playback compatibility analyzer | ✅ | ✅ | ✅ | ➖ | ➖ | ➖ | ➖ |
| Deep links (`astra://`) | ✅ | ✅ | ✅ | ✅ | ✅ | ➖ | ➖ |

### Notes
1. Widgets and Top Shelf read the shared App Group container (`group.astra.ios`). They
   surface Continue Watching / library entries the app writes; they do not run the full
   Home engine.
2. Background: audio/scrobble continuity depends on background-audio entitlement and the
   chosen "leave player" behavior (currently pause-on-leave / resume-on-return). True
   background video is not enabled.
3. On tvOS, external-player hand-off is limited by what third-party tvOS players expose.

### Not yet in the build (tracked, not shipped)
SharePlay watch parties · iPhone-as-Apple-TV-remote · Plex/Jellyfin/Emby · WebDAV/SFTP/NFS ·
Live TV time-shift & recording · device hand-off · timeline thumbnails · embedded chapters.
These require external SDKs, entitlements, or server infrastructure and are intentionally
not represented with non-functional UI.
