# Nova for Apple Watch — 2026-09-14

## Scope and implementation

Nova now includes a real, dependent watchOS 26 SwiftUI application, embedded in the iPhone app. Its shared scheme is `Nova-watchOS`, its bundle identifier is `com.nova.app.ios.watchkitapp`, and its companion identifier is the existing `com.nova.app.ios`. It reuses Nova's existing icon without changing the iOS/tvOS artwork. The project-wide QA numbering script stamps the watch and phone consistently.

The watch supports:

- A cached home with library counts, synchronization time, pending edits, and connection status.
- Search and paginated access to the **entire saved iPhone library**, including filtered Continue Watching, Favorites, Up Next, and History lists. Online pages contain up to 25 titles; offline lists identify that they show the bounded cache.
- Title details with episode/year metadata, runtime where known, recorded progress, and last-played date. Unknown runtimes remain unknown.
- Explicit favorite/unfavorite, add/remove Up Next, and watched/unwatched changes. Clearing progress requires confirmation; optimistic state stays distinct from confirmed iPhone results. Marking an unknown-runtime title watched returns a request to refresh its iPhone metadata, rather than inventing a runtime to manufacture completion.
- Watch Night plan summaries and individual full-plan requests, including plans outside the snapshot. Create, rename, schedule/time budget, add a library title, remove an entry (even if its original library title is gone), and delete with confirmation use the existing iPhone Watch Night store.
- Current iPhone AVPlayer/VLC status and explicit pause/resume, supported absolute seek via ±15-second controls, and supported player volume. The player must actually be registered, ready, and on the foreground iPhone. Switching players changes the session identifier; stale commands cannot control the replacement.
- “Open on iPhone” requests the corresponding saved-title detail through Nova's existing Library navigation. The iPhone must be foreground and its root handler available. The receipt says the title was requested; the user chooses Play on iPhone.
- Recent operation receipts, manual sync, clear offline labels, and explicit local watch-cache recovery. Resetting this cache discards unsent watch edits, cancels outstanding queued transfers, and clears transient search/plan data only after confirmation. The confirmation explains that work already delivered to iPhone may still complete.

The watch does **not** play movies, resolve provider streams, browse SMB shares, configure credentials, manage downloads/subtitles, or show private Watch Night notes. These remain iPhone workflows. Existing Watch Night breaks and advanced plan editing remain on iPhone. This pass does not add complications. Physical device UI parity or background-delivery latency has not been claimed.

## Data, reliability, and privacy

`NovaWatchShared/NovaWatchProtocol.swift` defines version-1, app-specific Codable projections, commands, receipts, an outbox, and a phone receipt journal. No playback URL, source path, server credential, account token, or private note is included. A SHA-256 local title key supports plan identity without transferring the underlying source key. Display strings have byte/character bounds; numeric source values are not converted into invented runtime estimates. Plan title text may be shortened for transfer while underlying iPhone titles remain intact.

The watch caches at most 120 selected titles and a byte-bounded selection of full plans; all titles and plans remain available through on-demand requests. Ordinary envelopes are limited to 60,000 bytes; snapshot content targets 24,000 bytes to reserve receipt space. Disk reads are capped at 512,000 bytes and reject nonregular files/symlinks. Atomic writes use file protection on iOS/watchOS. Unreadable originals are preserved and editing is disabled; only an explicit local recovery/reset replaces them.

The persistent outbox holds up to 100 **durable** library/plan commands. UUIDs and monotonically increasing per-watch sequence numbers survive relaunch. Only the first durable command is dispatched until its receipt arrives. The iPhone serializes received work and persists a reservation before mutation, then records an outcome. An interrupted reservation reports uncertainty rather than replaying a stale change. Matching receipts and sequence high-water marks make retries idempotent, including after receipt-history eviction. Successful title edits return an authoritative title projection, so an off-cache detail does not revert after its optimistic overlay is removed.

Phone epochs change across explicit library/history resets, explicit cloud-library replacement, backup restore, and Watch Night reset boundaries. Persisted cloud-deletion watermarks cover resets observed after relaunch. Automatic reconciliation cannot overwrite an unreadable phone journal. Old-epoch commands are rejected. After initial synchronization, a different epoch can replace the watch cache only in a correlated live refresh response; delayed old application contexts cannot roll it back. Old unsent edits are reported as discarded instead of being applied to replacement data.

Search/refresh/plan reads use reachable messages. Player controls and phone handoff expire after 20 seconds, require the correct active player session where applicable, and are never placed in the offline outbox. Durable edits can use background `transferUserInfo`; state uses the latest `updateApplicationContext`. Session activation is owned by AppEnvironment construction, including a background phone launch. Delegate callbacks explicitly hop to MainActor; iOS deactivation reactivates the session. The watch `.backgroundTask(.watchConnectivity)` handler waits for activation/content delivery and queued actor callbacks, subject to cancellation and a bounded wait.

Library title projection, hashing, sorting, and search filtering run off the main actor. Projection work is coalesced on library/queue changes; cancellation propagates to its worker, and revision checks precede publication. The phone does not repeatedly sort the library while idle. Small player snapshots refresh while a reachable watch and foreground phone player are active.

## Source map

| Files | Responsibility |
| --- | --- |
| `NovaWatchShared/NovaWatchProtocol.swift` | Wire/disk types, validation, idempotency, epoch/overlay/live-control policies |
| `NovaWatchShared/NovaWatchConnectivity.swift` | WCSession lifecycle, bounded messages, background delivery and callback tracking |
| `Nova/Services/Watch/NovaPhoneWatchBridge.swift` | Phone authority, projections, serialized mutations, receipts, reset boundaries |
| `Nova/Services/Watch/NovaWatchRemotePlayer.swift` | Real AVPlayer/VLC status and guarded controls |
| `NovaWatch/NovaWatchStore.swift` | Persistent watch cache/outbox, receipt processing, pagination and optimistic overlays |
| `NovaWatch/NovaWatchApp.swift` | Native watch navigation and workflows |
| `Nova/App/AppEnvironment.swift`, `NovaApp.swift`, `Nova/Views/RootView.swift` | Launch activation, foreground lifecycle, existing Library detail handoff |
| `Nova/Services/PlaybackCoordinator.swift`, `LibraryStore.swift` | Active player identity and explicit destructive reset hooks |
| `Nova.xcodeproj`, `NovaWatch/Info.plist`, `NovaWatch/Assets.xcassets` | Target, embedding, scheme, dependent companion identity, icon |
| `Nova/Services/UnifiedQAReporter.swift` | Eight new Apple Watch physical-device journeys; no automatic pass verdicts |

## Validation

- `scripts/run_watch_protocol_checks.sh`: **60 optimized native checks passed**; captured output: `/tmp/nova-watch-protocol-checks.log`. Covers bounded/invalid payloads, huge Unicode plan transfer, snapshot epochs/order, pending state, uncached title acknowledgement, journal crash reservation and restart deduplication, sequence gaps, capacity recovery, expiry/session input rules, corrupt files, symlinks, file size, and exact persistent outbox UUID/order.
- Generic watchOS build passed with watchOS 27 SDK and a watchOS 26 deployment target.
- Generic iOS build and packaging audit passed during implementation: embedded watch companion ID, actual Mach-O platforms, family 4, icon asset and synchronized build versions were inspected.
- Final generic builds passed: iOS plus embedded watch **1.7 (196)**; tvOS **1.7 (193)**. The standalone watch scheme also passed. Existing QA reporter actor-isolation warnings and AMSMB2 Makefile resource warnings remain; the watch target only reports the normal no-AppIntents metadata notice. No simulators, physical-device installs, real provider endpoints, or personal data were used for validation.

Eight QA/checkbook journeys remain **open**: pairing/sync, offline/background acknowledgement, epoch reset, full-library/off-cache edit, Watch Night lifecycle, real AVPlayer/VLC controls and expiry, phone handoff, and watch accessibility. Test these with a paired watch/phone before treating the companion as device-validated.

## Platform references

- [Apple: Transferring data with Watch Connectivity](https://developer.apple.com/documentation/watchconnectivity/transferring-data-with-watch-connectivity)
- [Apple: WCSession](https://developer.apple.com/documentation/watchconnectivity/wcsession)
- [Apple: WKCompanionAppBundleIdentifier](https://developer.apple.com/documentation/bundleresources/information-property-list/wkcompanionappbundleidentifier)
- [Apple: Watch connectivity background tasks](https://developer.apple.com/documentation/watchkit/wkwatchconnectivityrefreshbackgroundtask)
