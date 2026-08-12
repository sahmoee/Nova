# Nova

Nova is a local-first personal media experience for iPhone, iPad, and Apple TV. It unifies a user’s own media sources, library, discovery, playback progress, profiles, optional services, and private backup in a fast native interface.

Nova does not provide media or access to third-party content. Users are responsible for the sources they connect and for having permission to access them.

## Highlights

- Native SwiftUI experiences for iOS, iPadOS, and tvOS
- Personal library, favorites, history, profiles, and continue watching
- SMB shares, Live TV playlists, direct URLs, and user-installed add-ons
- Nova Tracker cross-device history, watchlist status, and ratings
- Optional Trakt, SIMKL, TMDB, OMDb, OpenSubtitles, and Real-Debrid integrations
- Apple and VLCKit playback paths
- Anime discovery, airing calendar, and availability-aware notifications
- Private iCloud configuration backup and portable `.nova` snapshots
- Internal iOS QA tickets with screenshots, automatic retry/sync, fix explanations, verification, and refiling

## Requirements

- macOS with [Xcode](https://developer.apple.com/xcode/)
- iOS 26 and tvOS 26 SDKs
- An Apple development team for signed device builds
- Optional AI and sharing features use the [Unified Worker](https://github.com/sahmoee/UnifiedWorker) at `https://api.sowensstudios.com/nova`

## Setup and build

```bash
git clone https://github.com/sahmoee/Nova.git
cd Nova
open Nova.xcodeproj
```

Choose **Nova-iOS** or **Nova-tvOS**, configure signing, and run on a connected device. Optional provider credentials are entered in-app under Settings and must never be committed.

Generic iOS device build:

```bash
xcodebuild -project Nova.xcodeproj \
  -scheme Nova-iOS \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

## Repository map

| Path | Purpose |
| --- | --- |
| [`Nova/`](Nova/) | Shared and iOS/tvOS application sources |
| [`NovaWidgets/`](NovaWidgets/) | Widget extension |
| [`Tests/`](Tests/) | Unit and regression tests |
| [`AGENTS.md`](AGENTS.md) | Mandatory coding-agent and QA workflow |
| [`CHANGELOG.md`](CHANGELOG.md) | Release history |

## Configuration

Nova’s integrations are optional. The app should remain useful when a provider is absent or offline. Store credentials in Keychain-backed settings or the configured secret pipeline; never place keys in source, project files, screenshots, or issue text. See [`SECURITY.md`](SECURITY.md) and [`PRIVACY.md`](PRIVACY.md).

## QA workflow

Nova iOS includes an internal QA queue. Tickets save locally before network work and then synchronize through the Unified Worker. Each fixed ticket contains a “What was fixed” resolution. The tester completes the lifecycle with **Verify Fix**, or chooses **Refile — still broken** to reopen it with preserved history and fresh evidence.

Synced artifacts are materialized under `Documents/Reports/Nova` in the shared workspace. All coding agents must follow [`AGENTS.md`](AGENTS.md).

## Contributing

Check the shared QA inbox before planning. Preserve iOS/tvOS behavior where code is shared, keep provider failures graceful, add regression coverage, build the affected schemes, and update release/cross-project documentation.

## License

See [`LICENSE.md`](LICENSE.md), [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md), and Apple’s [user privacy guidance](https://developer.apple.com/app-store/user-privacy-and-data-use/).
