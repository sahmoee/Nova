# Nova — 40 additional code improvements, pass 3 (2026-09-14)

This is a code-focused pass following the cache/polish pass. It does not recount that work or add UI features. Changes apply to the shared iOS/iPadOS and tvOS implementation. Existing dirty changes are preserved.

## Media indexing: improvements 1–20

The exact provider/client/store corrections and fixtures are in [the media indexing submanifest](CODE_PASS_3_MEDIA_INDEX_2026_09_14.md). Its numbered 1–20 entries are the first twenty improvements in this pass.

## Library reliability and performance: improvements 21–40

21. **Bound local reads before decoding.** `LibraryFilePolicy` checks regular-file metadata, rejects symlinks, and bounds the actual file-handle read to 128 MiB for library JSON and 8 MiB for collections. Oversized inputs cannot trigger an unbounded `Data(contentsOf:)` allocation.
22. **Protect an unreadable library.** A failed decode now preserves the original file and blocks ordinary saves/reindexing. Explicit valid cloud restoration or a Settings library reset can recover it; an empty launch view no longer replaces the file.
23. **Protect unreadable collections separately.** An existing bad collections file is no longer treated as missing and silently replaced by cloud/empty data. Its independent recovery guard preserves it until explicit recovery.
24. **Recover missing persistence directories.** Atomic library/collection writes recreate their Application Support parent instead of depending on a directory created only during startup.
25. **Roll back failed local mutations and retire their cloud writes.** A durable in-memory library snapshot restores the last successful state after save failure; the old pending cloud debounce is cancelled. Explicit cloud pushes also require successful local persistence first.
26. **Accept remote library revisions only after local save.** Cloud adoption writes before publishing or advancing the accepted revision, validates finite revisions, cancels a pending echo and refreshes Spotlight/widget consumers. Failed explicit pulls preserve the previously accepted revision.
27. **Make collection mutations report real persistence success.** Creation, rename, membership changes and deletion write a candidate before publishing it. Creation returns an optional result; AI/detail/collection callers do not claim successful creation when it failed. Blank names and unchanged renames do not write.
28. **Index bulk library imports.** Batch addition performs keyed O(existing + incoming) lookup work and publishes once, preserving single-add ordering and durable watch state instead of repeatedly scanning/inserting the library for every imported title.
29. **Make bulk favorite/hide operations one pass.** Set membership replaces one full lookup per selected UUID; a candidate array publishes once, and unchanged requests do not encode or sync.
30. **Make bulk tagging one pass.** The same candidate strategy avoids repeated publication and scanning, trims newlines as well as spaces, rejects blank tags, and preserves case-insensitive duplicate handling.
31. **Reject nonfinite subtitle offsets at mutation time.** NaN/infinity can no longer cause whole-library JSON encoding to fail; repeated offsets do not rewrite the file.
32. **Index ordered collection and queue projections.** A single lookup table replaces repeated `items.first` searches; missing/repeated references are skipped while requested order is preserved.
33. **Keep an intentionally empty local queue empty.** Valid local queue data now wins even when empty; a stale cloud queue is adopted only when no readable local queue exists.
34. **Normalize restored queue identities.** Launch and explicit cloud pulls deduplicate UUIDs in stable order, preventing repeated queue rows/actions without discarding references for temporarily unavailable titles.
35. **Validate queue moves.** A pure reorder policy checks every source index and destination before mutation, handles noncontiguous moves correctly, and suppresses unchanged moves rather than risking out-of-bounds failures from stale UI state.
36. **Match refreshed server items by native identity first.** Connection UUID + provider item ID, including alternate locations, retains a saved row's UUID and watch state when provider metadata or fallback content keys change.
37. **Preserve collection membership during key migration.** Reconciliation maps changed content keys and temporarily saves both old/new references before replacing library JSON, then deduplicates to the new keys. An interrupted two-file replacement retains a resolvable reference rather than losing the collection entry.
38. **Preserve useful saved metadata while refreshing locations.** Merge retains legal-access acknowledgement, existing artwork and skip segments when incoming metadata omits them. Newly refreshed alternate locations win over older URLs with the same native identity.
39. **Report durable, scoped reconciliation results.** Wrong-connection input is rejected without deletion; unchanged valid snapshots succeed without rewriting; save failures return false to `MediaServerStore`, which does not advertise a successful index. Removed primary locations still promote surviving alternates.
40. **Make duplicate merging operate on current state.** Duplicate groups have stable identities and distinguish movie/series/live namespaces. A shared bridge-and-commit helper protects collection/queue references if either persistence step fails. Merge revalidates current rows rather than stale sheet snapshots, preserves current tags/consent/alternate locations, and remaps queued IDs to the survivor so plans do not disappear.

## Ownership and compatibility

`MediaServerClient` produces complete validated read-only indexes; `MediaServerStore` owns credentials/configuration and async operation lifetimes; `LibraryStore` owns local persistence and reconciliation. `LibraryMutationPolicy` and `LibraryFilePolicy` are shared production logic tested with disposable fixture data.

Existing JSON field schemas and UnifiedWorker endpoints are unchanged. Server fallback *values* now include the connection UUID; existing saved rows migrate through native source identity. Older installed clients remain able to decode the files but can reintroduce the older fallback keys when indexing; update both Nova device apps for consistent behavior. Provider servers remain authoritative for availability, and local Nova remains authoritative for watch state and collections. No server, credential, cloud-account or personal-library mutation was performed during verification.

The library/collection files remain separate JSON files, not a database transaction. The bridge protects membership across an interrupted reconciliation; failed final cleanup may leave redundant old/new keys until the collection is edited/cleaned up. iCloud delivery and provider behavior still require connected-device checks.

## Validation

- Production-library native runner: `scripts/run_library_reliability_checks.sh` — **69 checks passed**. It compiles the actual store/models/policies with isolated cloud/widget/Spotlight adapters and disposable filesystem/UserDefaults fixtures.
- Media index runner: **88 native Swift 6 checks passed**, with actual provider-client/store/policy sources and isolated dependent adapters. Together this pass adds **157 passing Nova checks**.
- Final unsigned generic device builds passed: **Nova-iOS 1.7 (185)** and **Nova-tvOS 1.7 (186)**. The iOS widget dependency built with the app. Logs: `/tmp/nova-pass3-ios-20260914.log` and `/tmp/nova-pass3-tvos-20260914.log`.
- Independent review caught and corrected duplicate-merge reference rollback and dependent-cloud-pull ordering; dedicated partial-write fixtures now pass. `git diff --check` passed. Existing AMSMB2 Makefile-resource warnings remain; no new build errors.
- No simulator execution, physical-device installation, live indexing or iCloud account test.
