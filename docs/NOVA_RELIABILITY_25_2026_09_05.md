# Nova: 25 implemented reliability improvements

This is the core/playback/network half of the 50-improvement Nova batch. It preserves the library, download v1 JSON/state values, content identities, credentials, original URLs and existing UI APIs. These are wired into current request, transfer and playback paths, not unused utilities.

## Implemented checklist

| # | Improvement and previously observed risk | Live implementation |
|---|---|---|
| 1 | Interpret HTTP-date `Retry-After`, as well as delta seconds, so dated provider cooldowns work. | `AppNetworking.retryAfterSeconds` → `MediaReliabilityPolicy.retryAfter` |
| 2 | Reject negative, NaN, infinite and overflowing cooldown values; these previously flowed toward sleep conversions. | `MediaReliabilityPolicy.retryAfter` |
| 3 | Treat provider cooldown as a minimum, never shorten it with negative jitter or deadline clipping. | `withRetry` → `retryDelay` |
| 4 | Use a monotonic retry budget and recheck it after sleeping; wall-clock changes cannot create extra retry attempts. | `NetworkRetry.withRetry` |
| 5 | Bound attempts and normalize non-finite/negative delays, preventing invalid scheduling and unbounded retry configuration. | `withRetry` / `boundedInterval` |
| 6 | Check cancellation before joining a shared GET and after its result; one cancelled consumer cannot publish stale data or cancel other consumers. | `AppNetworking.GETCoalescer.data` |
| 7 | Normalize invalid/extreme JSON request timeouts while retaining caller headers and explicit overrides. | `AppNetworking.getJSON/postJSON` |
| 8 | Require HTTP JSON responses and reject cancelled responses before decode; set a default JSON Accept header. | `AppNetworking.getJSON/postJSON` |
| 9 | Reject non-success HTTP download responses and HTML/JSON error payloads instead of marking them complete movies. | `DownloadManager.didFinishDownloadingTo` |
| 10 | Reject zero-byte remote and local files; reconciled/offline playback checks require a nonempty regular file. | `validDownloadResponse`, `copyLocalFile`, `validOfflineFile` |
| 11 | Pause only active/queued records, suppress duplicate pause cancellation and clear transfer-rate state on completion. | `DownloadLifecycleState.canPause`, `DownloadManager.pause/pauseAll` |
| 12 | Resume only paused records without an existing task; persist the transition and avoid duplicate tasks. | `canResume`, `DownloadManager.resume` |
| 13 | Retry only failed records; a repeated/programmatic retry cannot delete an already completed file. | `canRetry`, `DownloadManager.retry` |
| 14 | Ignore progress callbacks from removed, replaced or intentionally pausing tasks so stale bytes/rates cannot mutate another transfer. | `DownloadManager.didWriteData` |
| 15 | Stage delegate temporary files, then verify task/record ownership before atomically committing; removing a download cannot resurrect it via a late success callback. | `DownloadManager.didFinishDownloadingTo` |
| 16 | Verify task identity before processing errors; intentional-pause callbacks own resume-data persistence and cannot remove replacement tasks. | `DownloadManager.didCompleteWithError/pause` |
| 17 | Preserve URLSession resume data from connectivity failures for the next automatic attempt. | `DownloadManager.didCompleteWithError` |
| 18 | Replace immediate connectivity retry loops with cancellable 1/2/4/8/16-second waits and a recoverable failure after five retries; other queued work still progresses. | `downloadBackoff`, `retryTasks`, `pumpQueue` |
| 19 | Process recovered/resumed local-file work without requiring a network connection or misrouting it into HTTP download tasks. | `DownloadManager.pumpQueue` |
| 20 | Restrict offline deletion/playback to the exact transfer's file in the owned media directory; validate resume filenames and reject path traversal, external files and another transfer's records. | `ownedDownloadFile`, `resumeFilename`, `removeFiles`, `validOfflineFile` |
| 21 | Remove legacy UserDefaults download data only after a successful atomic file write; disk-full/write errors retain the migration fallback. | `CodableFileStore.save` returns success; `DownloadManager.loadPersisted` |
| 22 | Repair recovered transfer metrics, invalid resume filenames, missing completion locations and retry counts; clamp aggregate progress and avoid storage-total overflow. | `DownloadManager.recovered`, `aggregateProgress`, `storageBytes` |
| 23 | Normalize invalid playback durations/positions/subtitle offsets on construction and legacy decode; computed progress/resume remain finite even after mutation. | `MediaItem`, `validDuration/validPosition/progress/canResume` |
| 24 | Use the persisted valid duration when a save callback omits/invalidates duration, so exact-end detection remains correct without losing late-title resume positions. | `PlaybackProgressStore.save` |
| 25 | Do not create stale VOD checkpoints for live channels, and do not advertise old live positions as resumable. | `PlaybackProgressStore.save`, `MediaItem.hasResumePoint` |

## Verification

- `scripts/MediaReliabilityChecks.swift`: **58 native host checks passed** against production `MediaReliabilityPolicy.swift` and `NetworkRetry.swift`. Covers header/date parsing, numerical bounds, cooldown/deadline interaction, actual transient/permanent retries, pre/post-response cancellation, state permissions, response validation, path/record isolation and backward-compatible download-state encoding.
- `Tests/MediaReliabilityTests.swift`: eight app regression tests added, including actual `MediaItem` decoding and derived state. Compilation/device execution are coordinated by the parent batch; no simulator execution performed here.
- Changed Swift sources passed syntax parsing.
- The app-wide iOS/tvOS build result belongs to the parent batch, not to this report. No build, upload, deployment, Git push or production API change was performed by this subtask.

Native reproduction:

```sh
xcrun swiftc -parse-as-library Nova/Services/MediaReliabilityPolicy.swift Nova/Services/NetworkRetry.swift scripts/MediaReliabilityChecks.swift -o /tmp/nova-media-reliability-checks
/tmp/nova-media-reliability-checks
```

## Ownership, compatibility and rollout

- **Owner:** Nova. Producers: current JSON providers and URLSession callbacks. Consumers: iOS/tvOS request clients, offline download UI/player, library progress displays and playback controllers.
- **Shared/API impact:** no Worker, Tracker, website, widget schema, host, credentials or metered model changes. `DownloadLifecycleState` keeps all five existing raw strings; `OfflineDownload.State` is a source-compatible alias. The additional file is required in both platform build phases.
- **Rollout:** app source/policy/tests together, then device builds and physical-device QA. No provider deployment is required.
- **Fallback/repair:** optional request failures remain recoverable. Existing local download records and media are preserved. Invalid restored references are marked failed rather than followed/deleted. Failed migration retains the legacy blob. Retry/backoff is bounded and manually retryable. Library records retain their IDs and content keys; malformed numerical fields repair on decode.
- **Limits:** native tests do not simulate physical URLSession delegate delivery, app termination, a real disk-full device, VLC/AVPlayer seeking, or tvOS focus. Device QA should test pause/resume/remove while a transfer finishes, interrupted network recovery, local copies while offline, a 404/empty download, and late-title resume. The retry budget prevents starting further attempts after its deadline; it does not forcibly interrupt an arbitrary already-running operation (URLSession retains its own timeout).
- **No destructive cleanup:** no existing user downloads or library entries were deleted by this implementation task.
