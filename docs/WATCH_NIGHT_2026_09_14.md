# Watch Night: six features and ten polish improvements

Implemented 2026-09-14 for iOS, iPadOS, and tvOS. This is the Watch Night portion of Nova's larger ten-feature pass.

Entry points: **Library → options → Watch Night** on iPhone and Apple TV; **Library → Watch Night** in the regular-width header on iPad. All title-opening actions reuse Library's existing direct-play or detail routing, including its source reconnect handling.

## Six new features

| # | Feature | Reachable behavior and implementation |
| --- | --- | --- |
| F1 | Ordered Watch Night plans | New plan, add library titles, move earlier/later, remove a title, and reopen that title. Up to 30 named plans with 40 titles each. `WatchNightPlan`, `WatchNightPlanView`, `WatchNightPlanEditor`. |
| F2 | Find a title that fits | Enter an available-time preset; compare full or remaining runtime, optionally show unwatched titles and movies only. Closest fits come first. `WatchNightLogic.fitting`, `WatchNightPicker`. |
| F3 | Compare up to three titles | Compare runtime, remaining time, source, watched state, and favorite state from existing library metadata; open title options or replace candidates. `WatchNightCompareView`. |
| F4 | Private viewing notes | Create, edit, search by title, reveal/conceal spoilers, and explicitly delete a personal note without changing ratings or watch history. `WatchNightNote`, `WatchNightNotesView`, `WatchNightNoteEditor`. |
| F5 | Lineup schedule and finish estimate | Choose a starting time, time budget, and breaks; show each known start time, estimated finish, and a budget-overrun notice. Refresh a saved runtime from current library metadata. iPhone/iPad offer a date picker; Apple TV offers relative start-time choices. `WatchNightPlan.knownSeconds`, `startDate`, `estimatedEnd`, and plan schedule UI. |
| F6 | Reviewed portable plan import/export | Export a plan JSON file on iPhone/iPad; import a file there or paste JSON on either platform. Preview title matches and explicitly save a new copy. Apple TV offers a read-only **View JSON**, not a claimed file exporter. Private notes, playback addresses, and credentials are not part of the portable format. `WatchNightPortablePlan`, `WatchNightImportView`. |

These use local library metadata and do not add an acquisition service, automatic playback, reminders, AI service, or cloud synchronization.

## Ten polish improvements

| # | Improvement | Evidence |
| --- | --- | --- |
| P1 | Explicit addition and selection feedback | Plans already containing a title show a checkmark and “Added to …”, disable duplicate addition, and expose the selected accessibility trait. Successful additions receive a readable confirmation. `WatchNightTitleActions`. |
| P2 | Recoverable empty, loading, and search states | Separate loading/searching indicators; explain empty libraries, no matches, missing plans, and unreadable saves. Clear search/reset filters and retry loading are reachable. `WatchNightView`, `WatchNightPicker`. |
| P3 | Bounded result rendering | Lazy results reveal 40 titles at a time, show the exact match count, and reset paging when the query or filters change. No full-library stack is rendered. `WatchNightPicker`. |
| P4 | Cancellable library and search work | Debounced library projection hashes and filters off the main actor; cancellation reaches its detached worker and stops scanning/sorting. Search/filter work is also debounced and cancelled before stale results publish. `WatchNightStore.refreshLibrary`, `WatchNightPicker.updateResults`. |
| P5 | Honest unknown-time and source matching feedback | Unknown runtimes never produce an exact finish, and later start times stop after an unknown predecessor. Conflicting or ambiguous portable identifiers never silently fall back to a similarly named title. Missing local matches remain visibly unresolved. `WatchNightLogic.matching`, plan/import rows. |
| P6 | Validated drafts with reliable saving | Plan/note editors require explicit Save or Cancel, show input limits, and disable dismissal during saving. State publishes only after successful atomic disk writes; unreadable existing files stay intact and read-only until recovery or explicit reset. Concurrent reloads coalesce. `WatchNightDisk`, `WatchNightStore`, editors. |
| P7 | Safer ordering and repeated actions | Move controls disable at lineup boundaries. Latest plan/entry identities are resolved before runtime refresh or addition; duplicate lineup and comparison selections are rejected with errors. Controls disable during persistence. `WatchNightPlanView`, `WatchNightTitleActions`, `WatchNightCompareView`. |
| P8 | Deliberate deletion and reset behavior | Plan deletion asks first and offers one-step undo; notes require deletion confirmation. Explicit Library reset deletes plans, notes, and corrupt saved files, reports failures, dismisses drafts, and clears the undo buffer so old private data cannot reappear. Reset UI is wired by the parent task. `deleteAllLocalData`, `resetRevision`, iOS/tvOS Settings reset handlers. |
| P9 | Consistent, readable controls and artwork | Shared `novaRowStyle`, `refinedCardBackground`, and poster radius follow the app's neutral glass/focus system. Adaptive action and comparison grids accommodate available width; cached artwork has a stable fallback and is excluded from duplicate VoiceOver announcements. Text rows combine their meaningful accessibility content. |
| P10 | Bounded, private document handling | Reads and writes have byte caps, imported dates/runtime/text/identities are validated, and JSON decoding runs off the main actor. iOS/tvOS local saves use atomic protected-file writes. Spoiler notes start concealed and conceal again on navigation or backgrounding. Notes are excluded from all plan exports and Nova setup snapshots/iCloud mirrors. |

## Validation

- `xcrun swiftc Nova/Models/WatchNight.swift scripts/WatchNightChecks.swift -o /tmp/nova-watch-night-checks && /tmp/nova-watch-night-checks` — **37 checks passed**.
- Fixtures cover full/remaining runtime, unknown time, schedule/break arithmetic, budget overrun, portable round-trip with new identities, byte/grapheme limits, invalid dates including extreme finite values, malformed identity, duplicate plans, and conflicting/ambiguous title matches.
- Swift frontend parse passed for the three new app files after the final changes.
- Parent task's first generic iOS build passed. Parent owns final iOS/tvOS incremental-build results for the combined Nova changes.
- No simulator, personal-data deletion, cloud transfer, or physical-device focus review was performed. Generic builds do not establish pixel-level visual parity.

## Ownership and storage

`WatchNightStore` owns `Application Support/watch-night.json` (schema version 1, maximum 4 MiB). Only plans explicitly exported by the user use the portable 512 KiB JSON contract. IMDb/TMDB identifiers or a unique title/year can reconnect a plan to another device's library; local identities are SHA-256 digests of existing content keys, never raw source URLs. Existing setup snapshot/iCloud schemas and UnifiedWorker contracts are unchanged. Removing this feature requires explicitly preserving or deleting its local file, not silently importing notes into another store.

Final integration: generic iOS and tvOS builds passed after the shared polish and platform-availability fixes. See [combined validation record](NOVA_30_IMPROVEMENTS_2026_09_14.md). No simulator or device execution was performed.
