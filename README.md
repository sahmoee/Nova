# Nova

A local-first personal media experience for iPhone, iPad, and Apple TV — your own
library and services in a fast, cinematic interface with universal search, watch
progress, profiles, optional AI-assisted discovery, and private iCloud backup.

Nova does not provide media or access to third-party content. Users are responsible for
the sources they connect and for having permission to access their media.

## Features

- Native SwiftUI app for iOS, iPadOS, and tvOS
- Personal library, favorites, watch history, and continue watching
- SMB folders, Live TV playlists, direct media URLs, and user-installed add-ons
- **Nova Tracker** — first-party cross-device watch tracking (history, watchlist statuses,
  ratings) that syncs via your iCloud identity; a built-in Trakt/SIMKL replacement
- Optional Trakt, SIMKL, TMDB account, OMDb, OpenSubtitles, and Real-Debrid integrations
- One-time import of your watchlist, watched history, and ratings from Trakt / SIMKL
- Optional AI discovery via a user-controlled Cloudflare Worker
- Private iCloud configuration backup and export (.nova snapshots)
- Apple and VLCKit playback engines
- Dedicated Anime catalog tab and an Airing Calendar of upcoming episodes for tracked shows
- Notifications when a new episode of a tracked show is actually available to stream
- Full accessibility: Dynamic Type, VoiceOver, adaptive layouts, tvOS focus

## Requirements

- Xcode 16 or later
- iOS 26 / tvOS 26 SDK

## Getting started

```bash
git clone https://github.com/sahmoee/Nova.git
cd Nova
open Nova.xcodeproj
```

Select the **Nova-iOS** or **Nova-tvOS** scheme, set your signing team, and run.
Optional integrations are configured in-app under Settings.

## Project structure

- `Nova/` — app sources
- `NovaWidgets/` — widget extension
- `Tests/` — unit tests

## License

See [LICENSE.md](LICENSE.md). Privacy in [PRIVACY.md](PRIVACY.md); third-party
components in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
