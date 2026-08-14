# Changelog

Every push should add an entry here so GitHub carries the build/change history.
Newest at the top. Keep it plain ASCII (see .gitmessage.txt for the commit rules).

## [Unreleased]

### Build 27 tracker, release calendar, and SMB playback
- Made Nova Tracker zero-setup for every install and cross-device through an opaque iCloud key-value identity, with server-side merging that preserves activity created before devices converge.
- Changed Calendar to show exactly one latest released episode per watched or library series, falling back to its next announced episode only when nothing has aired.
- Added iOS background refresh scheduling for newly released, streamable-episode notifications while retaining one notification per newest episode.
- Corrected SMB HTTP metadata, HEAD and byte-range handling for native AVPlayer, then transparently falls back to embedded VLC when a file or codec still cannot play natively.
- Marketing version remains 1.7.

### Build 26 cinematic tvOS home
- Rebuilt the Apple TV home around an edge-to-edge, artwork-driven featured backdrop with left-aligned title, genres, synopsis, Play, Up Next, info, and detail actions.
- Made the selected artwork color wash through the full home canvas and converted tvOS home/editorial shelves to large landscape cards with titles below, matching the supplied living-room reference.
- Retained the adaptive iPhone/iPad presentation and marketing version 1.7.

### Build 25 tvOS compilation repair
- Restored Nova-tvOS compilation by keeping iOS-only episode notification content and authorization behind the iOS platform boundary while preserving shared latest-episode availability tracking.
- Made the Unified QA suite tvOS-compatible for disk capacity, long-press feedback, checklist disclosure, and diagnostic-copy controls; corrected Trakt actor logout and the deprecated iOS poster-grid group API.
- Marketing version remains 1.7.

### QA and documentation
- Fixed My Nova SMB items so folder imports retain stable share/path identity, automatically enrich missing poster/backdrop art, reconnect and rebuild temporary stream URLs, and play directly instead of incorrectly querying addons for sources.
- Expanded Nova QA with opt-in tap/navigation breadcrumbs, lifecycle and memory-warning capture, an on-device accessibility sweep, and shipped fix records for NVA-23-0001 and NVA-23-0002 pending tester verification.
- Rebuilt Nova QA as an opt-in, app-specific test suite with global press-and-hold reporting, pre-composer screenshots, playback/source/library/SMB/download/network context, memory and hitch monitoring, sync state and retry, ticket history, fix notes, verification, and refiling.
- Added long-press movie and episode downloads, a Downloads entry in My Nova, duplicate-transfer protection, and a persistent pause/resume/retry/cleanup manager.
- Collapsed every library-derived surface to one card per series represented by its most recently watched episode, and constrained calendars/notifications to one newest release per show.
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
- Cross-device identity now uses the existing iCloud key-value entitlement and requires no CloudKit compilation flag.
