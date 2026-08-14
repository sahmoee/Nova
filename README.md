# Nova

Nova is a local-first personal media experience for iPhone, iPad, and Apple TV. It combines a user’s own libraries and sources with discovery, metadata, playback, progress, profiles, optional tracking services, and private backup in a native SwiftUI interface.

Current app version: **1.7**. The project targets **iOS/iPadOS 26** and **tvOS 26**, with separate app schemes plus an iOS widget extension.

Nova does not provide media or access to third-party content. Users are responsible for the sources they configure and for having permission to access and play them.

## Brand assets

The approved Nova icon source is `Nova/Resources/Brand/Nova-AppIcon-Pastel-Master.png`. Regenerate every iOS and tvOS icon and Top Shelf variant together with:

```sh
python3 -m pip install -r requirements-brand-assets.txt
python3 generate_brand_assets.py Nova/Resources/Brand/Nova-AppIcon-Pastel-Master.png
```

The compatibility command `swift generate_brand_assets.swift <source.png>` invokes the same generator.

## Product capabilities

### Library and discovery

- Home, Discover, Library, AI, and Settings destinations with adaptive iPhone tabs, iPad sidebar, and tvOS focus UI
- Personal library, collections, favorites, history, watchlist, continue watching, duplicates, quality checks, and metadata correction
- Catalog browsing through user-installed add-ons, people/title detail, recommendations, airing information, and personalized shelves
- Search cleanup/correction, title rules, metadata parsing, library enrichment, and optional AI-assisted search/filtering

### Sources and playback

- SMB shares, direct URLs, Live TV/EPG sources, magnet/source resolution, and user-installed Stremio-compatible add-ons
- Source ranking, filtering, health history, retry, network-condition monitoring, and failure explanations
- Native and VLCKit playback paths, subtitle discovery/matching, subtitle picker, playback gestures, skip segments, and binge settings
- Progress, now playing, watch statistics, show settings, player memory, and Spotlight indexing

### Accounts, sync, and portability

- Optional TMDB, TMDB account, OMDb, Trakt, Simkl, OpenSubtitles, Real-Debrid, and compatible add-on integrations
- Keychain-backed secrets/tokens and provider-specific connection flows
- Local Codable stores and caches, offline catalog cache, download manager, and cleanup tools
- iCloud configuration backup plus portable `.nova` backup/restore snapshots
- Nova Tracker/shared-history support and encrypted one-time share storage through the Unified Worker

### Platform and operations

- Shared iOS/tvOS code with platform-specific navigation and playback behavior
- iOS widgets, changelog, setup checklist, guest/safe modes, diagnostics, privacy/legal disclosure, and internal QA reporting
- Registration and configuration guards that catch unregistered Swift sources and bundle-identifier drift

## Architecture

| Area | Key implementation |
| --- | --- |
| App lifecycle/environment | [`Nova/App/NovaApp.swift`](Nova/App/NovaApp.swift), [`Nova/App/AppEnvironment.swift`](Nova/App/AppEnvironment.swift) |
| Adaptive navigation | [`Nova/Views/RootView.swift`](Nova/Views/RootView.swift) |
| Library and metadata | [`Nova/Services/LibraryStore.swift`](Nova/Services/LibraryStore.swift), [`Nova/Services/LibraryEnricher.swift`](Nova/Services/LibraryEnricher.swift), [`Nova/Views/Library/`](Nova/Views/Library/) |
| Catalog and add-ons | [`Nova/Services/AddonStore.swift`](Nova/Services/AddonStore.swift), [`Nova/Services/StremioAddonClient.swift`](Nova/Services/StremioAddonClient.swift), [`Nova/Views/Catalog/`](Nova/Views/Catalog/) |
| Sources and playback | [`Nova/Services/StreamResolver.swift`](Nova/Services/StreamResolver.swift), [`Nova/Services/PlaybackCoordinator.swift`](Nova/Services/PlaybackCoordinator.swift), [`Nova/Views/Player/`](Nova/Views/Player/) |
| Provider integrations | [`Nova/Services/Tracking/`](Nova/Services/Tracking/), `Nova/Services/*Client.swift`, [`Nova/Services/KeychainStore.swift`](Nova/Services/KeychainStore.swift) |
| Backup, sync, offline | [`Nova/Services/BackupManager.swift`](Nova/Services/BackupManager.swift), [`Nova/Services/CloudSync.swift`](Nova/Services/CloudSync.swift), [`Nova/Services/OfflineCatalogCache.swift`](Nova/Services/OfflineCatalogCache.swift) |
| Widgets and tests | [`NovaWidgets/`](NovaWidgets/), [`Tests/`](Tests/) |

The app is local-first: provider outages should not corrupt the library, erase progress, or prevent playback of an otherwise reachable personal source. External metadata and tracking are enrichments, not the system of record for local data.

## Requirements

- macOS with [Xcode](https://developer.apple.com/xcode/)
- iOS 26 and tvOS 26 SDKs for both schemes
- An Apple development team for physical-device and Apple TV installation
- Network access to any user-configured servers/providers
- Optional [Unified Worker](https://github.com/sahmoee/UnifiedWorker) access for AI and sharing functions

VLCKit and SMB dependencies are resolved through Swift Package Manager and can consume significant DerivedData space. Prefer a physical-device workflow and place DerivedData on an external drive when local storage is constrained.

## Setup and build

```bash
git clone https://github.com/sahmoee/Nova.git
cd Nova
open Nova.xcodeproj
```

Select **Nova-iOS** or **Nova-tvOS**, configure signing, and run on the corresponding connected device.

Generic iOS device build:

```bash
xcodebuild \
  -project Nova.xcodeproj \
  -scheme Nova-iOS \
  -destination 'generic/platform=iOS' \
  -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO \
  clean build
```

Generic tvOS device build:

```bash
xcodebuild \
  -project Nova.xcodeproj \
  -scheme Nova-tvOS \
  -destination 'generic/platform=tvOS' \
  -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO \
  clean build
```

The tvOS SDK must be installed in Xcode. A missing tvOS platform is a local toolchain issue, not an application compile failure.

## Configuration

Most provider credentials are entered in-app under Settings and stored through Keychain-backed services. [`NovaConfig.example.json`](NovaConfig.example.json) documents the optional fallback file format; rename it to `NovaConfig.json` and place it in the app’s Documents directory or bundle it only for a controlled build.

| Value | Purpose | Notes |
| --- | --- | --- |
| `tmdbApiKey` | TMDB metadata | Optional |
| `traktClientId`, `traktClientSecret` | Trakt connection | Access tokens are never read from the file |
| `openSubtitlesApiKey` | Subtitle lookup | Optional |
| `aiWorkerUrl` | AI/search Worker override | Prefer the unified route |
| `novaTrackerBaseUrl` | Tracker endpoint override | Optional |
| `addonManifestURLs` | Initial user-configured add-ons | Only trusted HTTPS manifests |

Additional integrations—including OMDb, Simkl, TMDB account, Real-Debrid, SMB credentials, and Live TV sources—are configured in-app. Do not commit credentials, account exports, share URLs, or personal server addresses.

The production unified route is `https://api.sowensstudios.com/nova`. Server-side AI keys and optional shared tokens belong in Cloudflare secrets; see the Worker’s [`SECRETS.md`](https://github.com/sahmoee/UnifiedWorker/blob/main/SECRETS.md).

## Validation and testing

Run repository guards before building:

```bash
./validate_nova_config.sh
./bundleid-guard.sh
./verify_registration.sh
plutil -lint Nova.xcodeproj/project.pbxproj
```

[`Tests/`](Tests/) covers parser behavior, disk caches, backup compatibility, add-on security, Worker configuration, and stream filtering. Hosted CI dynamically selects an available iPhone simulator, tests iOS, and builds tvOS. Local simulator use is optional.

When adding a Swift file, ensure it is registered in every intended target. Shared code may require both iOS and tvOS source build phases; [`verify_registration.sh`](verify_registration.sh) checks this explicitly.

## Provider and content responsibilities

- Add-ons and source resolvers must be user-configured, transparent, removable, and failure-isolated.
- Nova must not bundle unauthorized catalogs, credentials, decryption material, or copyrighted media.
- Metadata providers may have attribution, image, caching, and rate-limit requirements; follow each provider’s current terms.
- Real-Debrid and tracking providers are optional user accounts and must fail without breaking local playback/library features.
- SMB secrets and provider tokens must remain in protected local storage and be excluded from logs, tickets, backups where inappropriate, and screenshots.

## QA and diagnostics

Nova iOS includes an internal QA queue. Reports save locally before network work, then synchronize through the Unified Worker with device/build context and optional screenshots. Fixed tickets require a “What was fixed” explanation; testers use **Verify Fix** or **Refile — still broken**.

Report synchronization is an internal development operation and is intentionally not documented in the public repository. In-app diagnostics and support surfaces include [`Nova/Views/Settings/DebugReportView.swift`](Nova/Views/Settings/DebugReportView.swift), safe mode, source health, network status, library health, and backup tools.

## Release checklist

- Update [`CHANGELOG.md`](CHANGELOG.md), [`APP_STORE_METADATA.md`](APP_STORE_METADATA.md), and in-app What’s New content.
- Increment iOS, tvOS, test, and widget versions/build numbers consistently.
- Run all configuration/registration guards, tests, and both affected platform builds.
- Verify real-device playback, SMB, subtitles, downloads, background/now-playing behavior, add-ons, metadata, backup/restore, provider sign-in, offline mode, and iPad/tvOS navigation.
- Review [`PRIVACY.md`](PRIVACY.md), [`SECURITY.md`](SECURITY.md), [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md), and personal-media disclosure.
- Archive each platform with Xcode and use TestFlight for distribution testing.

## Troubleshooting

- **Build consumes too much disk:** move DerivedData to an external drive and remove only known disposable build directories; do not delete the workspace.
- **Package resolution/VLCKit fails:** verify network access, resolved package versions, and sufficient disk space.
- **A Swift file appears ignored:** run `./verify_registration.sh` and inspect both platform source phases.
- **No playable source:** inspect source health, resolver/filter output, network state, provider/add-on configuration, and [`PlaybackFailureReason`](Nova/Services/PlaybackFailureReason.swift).
- **Metadata is wrong:** use Fix Match or cleanup rules, then refresh/enrich the affected item.
- **tvOS will not build locally:** install the matching tvOS platform in Xcode and select the `Nova-tvOS` scheme.
- **Backup restore is rejected:** retain the original backup and inspect compatibility validation before modifying migration logic.

## Security, privacy, legal, and support

See [`SECURITY.md`](SECURITY.md), [`PRIVACY.md`](PRIVACY.md), [`SUPPORT.md`](SUPPORT.md), [`LICENSE.md`](LICENSE.md), and [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md). Apple privacy guidance is available at [developer.apple.com/app-store/user-privacy-and-data-use](https://developer.apple.com/app-store/user-privacy-and-data-use/).

## Contributing

- [`CONTRIBUTING.md`](CONTRIBUTING.md) — contribution process
- [`docs/NOVA_RENAME_COMPATIBILITY.md`](docs/NOVA_RENAME_COMPATIBILITY.md) — naming and compatibility constraints

Preserve persisted-data and backup compatibility, keep shared iOS/tvOS behavior deliberate, add regression tests, avoid unsafe provider assumptions, and update all clients when a shared Worker contract changes.
