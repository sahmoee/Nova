# Changelog

Every push should add an entry here so GitHub carries the build/change history.
Newest at the top. Keep it plain ASCII (see .gitmessage.txt for the commit rules).

## [Unreleased]

### QA and documentation
- Expanded documentation across library/discovery, sources, playback, iOS/tvOS architecture, provider configuration, local storage, backup, testing, release operations, troubleshooting, privacy, and content responsibility.
- Added the iOS Unified QA ticket queue with automatic screenshots, device/build context, offline persistence, upload retry, required fix resolutions, tester verification, and history-preserving refiles.
- Added professional setup, build, configuration, security, contribution, and issue-reporting documentation.

### Added
- **Nova Tracker**: first-party cross-device watch tracking (history/scrobble, watchlist
  statuses, ratings) with an iCloud-shared identity, offline cache + delta sync, and a
  status/rating panel on the detail screen. Designed to replace Trakt/SIMKL.
- SIMKL and TMDB-account trackers alongside Trakt, behind a provider hub (writes fan out,
  reads merge) so trackers are optional and coexist.
- Anime catalog tab; Airing Calendar tab (upcoming episodes for tracked shows).
- Notifications when a new episode of a tracked show becomes streamable from your addons.
- One-time import of watchlist, watched history, and ratings from Trakt / SIMKL.
- Long-press Download: resolve the best stream and save movies offline from browse shelves
  and Home cards (iOS/iPadOS); enqueues into the existing Downloads manager.
- boxd-inspired cinematic theme, stream quality chips, watch-progress on poster art,
  Liquid Glass chrome, and horizontal card snapping.

### Fixed
- PosterCollectionGrid `Item.ID` Sendable conformance (Swift 6).
- ContentDetailView hero layout on compact iPhone widths.

### Notes
- True cross-device identity requires the iCloud ▸ CloudKit capability and the
  `NOVA_CLOUDKIT_IDENTITY` compilation condition on BOTH the iOS and tvOS targets.
