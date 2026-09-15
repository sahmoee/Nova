# Nova Sources: four new features and ten polish improvements

This is the Sources portion of the September 14 Nova pass. It complements the separately documented six Watch Night features and ten polish improvements. Sonarr stays optional and read-only on iOS, iPadOS, and tvOS.

## Four new capabilities

| # | Feature | Implementation |
|---|---|---|
| 1 | Searchable Sonarr series browser | Search names; filter all, monitored, missing, or files complete; sort by title, missing count, or file count. Results have stable ID tie-breaks and a matching/total count. `SonarrDashboard.seriesContent`, `SonarrDashboardPolicy.filterSeries`. |
| 2 | Per-series availability detail | Open a series to inspect episode-file count, expected episodes, missing estimate, total episodes, and disk usage. Absent statistics remain unavailable. Nova explicitly distinguishes Sonarr's counts from playable copies in Nova. `SonarrSeriesDetail`, `SonarrSeries.missing`. |
| 3 | Grouped, filterable episode calendar | Browse today, seven days, or thirty days; combine monitored/unmonitored and available/missing-file filters. Every matching episode is grouped under its local calendar date; air times use the device time zone. Removes the previous thirty-row display truncation. `calendarContent`, `filterEpisodes`. |
| 4 | Detailed queue inspector | Open loaded queue records for byte progress, downloaded/remaining sizes, Sonarr time-left/estimated completion, download client, health, error text, and status-message details. Optional warnings-only filter. All fifty loaded records are reachable; total versus loaded count explains the first-page limit. `SonarrQueueDetail`, `queueContent`, `SonarrQueueItem`. |

## Ten polish improvements

| # | Improvement | Implementation |
|---|---|---|
| 1 | Sonarr async changes actually repaint the dashboard | `SonarrView` passes the nested store into `SonarrDashboard` with `@ObservedObject`; it no longer relies on AppEnvironment to forward nested changes. |
| 2 | Media-server indexing progress and results repaint immediately | `MediaServersContent` observes `MediaServerStore` directly, and refresh errors are surfaced instead of discarded by `try?`. |
| 3 | Source controls adapt to narrow layouts and larger text | Adaptive metric grid, wrapping action/filter rows, full multiline server address, labeled indexed count, and a bounded reading width in the editor. Shared Nova styles preserve iOS action color and neutral tvOS focus. |
| 4 | Refresh state is truthful | Unknown initial statistics show a dash; the last successful refresh is dated; failed refreshes keep the previous snapshot with a stale-data explanation. Missing totals explicitly exclude unknown series statistics; warnings and queue totals distinguish loaded versus total. |
| 5 | Superseded network responses cannot revive a disconnected connection | Refresh and request publication check a configuration generation. Saving/replacing/disconnecting invalidates older work; its completion cannot reset a newer spinner or publish retired data/errors. Cancellation retains the previous snapshot. |
| 6 | Connection addresses and secrets follow validated save ordering | HTTP/HTTPS only, intact reverse-proxy paths, no credentials/query/fragment in addresses. A different Sonarr address requires its own key. Keychain writes must succeed before preferences change. Unchanged Save & Test retains a successful snapshot. |
| 7 | Both connection editors protect drafts and prevent overlapping saves | Cancel checks for edited drafts, interactive dismissal is guarded, busy controls disable while testing/indexing, and save methods reject duplicate starts. Sonarr initial values load only once; a failed test retains the current editable configuration. |
| 8 | Sonarr failures give usable recovery guidance | Authentication, missing v3 route, rate limiting, and other HTTP failures have distinct explanations. `Retry-After` uses the existing reliability policy and is honored before another refresh; replacing a same-server key does not shorten its cooldown. Whole and fractional ISO timestamps both decode. |
| 9 | Sonarr disconnect is explicit and reversible by reconnecting | Confirmation describes exactly what is removed; Keychain deletion errors keep the configured connection instead of falsely reporting disconnection. No series, files, or downloads are deleted. |
| 10 | Media-server credential and library choices describe actual behavior | Separate replacement token and replacement password fields route into their correct parameters. Changed server address/username requires new credentials. Empty library selection explicitly means index all. Successful save trims the display name. |

## Ownership and compatibility

- Nova owns `SonarrStore`, the new Foundation-only `SonarrDashboardPolicy.swift` models/policies, and the Sources UI. Both app targets must include the new file. No widget, Worker, site, database, download-management, or provider-authentication endpoint is added.
- Sonarr's existing v3 status, series, calendar, and queue endpoints remain the only producers. The calendar request now includes the documented `unmonitored=true` option so the new local filter has the required records.
- The existing preference key and Keychain account are unchanged. New response fields are optional. Old server payloads without queue metrics or statistics still display useful titles/status and clearly mark unavailable values.
- There are no POST/PUT/DELETE requests to Sonarr. It remains authoritative for monitoring, acquisition, import, and quality management. Queue progress is not an assertion that an episode was imported successfully.
- Queue detail is a snapshot when opened. Refresh the dashboard to fetch updates. The queue still requests its existing first fifty records and explicitly reports that limit; no unbounded polling or pagination was introduced.
- Legacy same-address keys are reused only for the same normalized address. Invalid credential-bearing addresses now require correction in Connection settings; secrets are not copied into URLs or logs.

Primary API references used to verify fields and query behavior: [Sonarr QueueResource](https://github.com/Sonarr/Sonarr/blob/develop/src/Sonarr.Api.V3/Queue/QueueResource.cs), [SeriesStatisticsResource](https://github.com/Sonarr/Sonarr/blob/develop/src/Sonarr.Api.V3/Series/SeriesStatisticsResource.cs), and [CalendarController](https://github.com/Sonarr/Sonarr/blob/develop/src/Sonarr.Api.V3/Calendar/CalendarController.cs). Accessed September 14, 2026.

## Verification

- **40 native fixture checks passed** in `scripts/SonarrDashboardChecks.swift`: safe base URLs/reverse-proxy joining, unknown/invalid counts, finite progress, actual `sizeleft`/`timeleft` wire names, fractional timestamps, message decoding, series filters and stable sorting, calendar monitoring/file combinations, local-day and DST boundaries.
- Swift source parse and `git diff --check` passed.
- Parent integration performs generic-device builds of both iOS and tvOS targets. Those results belong in the combined pass record; this document does not claim a completed build in advance.
- No simulator, physical-device interaction, Keychain mutation, or request to the user's actual Sonarr/media servers was used for validation. Live authentication, provider-specific responses, and remote-focus behavior remain device acceptance checks.

```sh
xcrun swiftc Nova/Services/SonarrDashboardPolicy.swift scripts/SonarrDashboardChecks.swift -o /tmp/nova-sonarr-dashboard-checks
/tmp/nova-sonarr-dashboard-checks
```

## Additional source and subtitle picker polish

Added after the user's broader selection, shape, and hover feedback; these are additional refinements, not new features counted above. Files: `Nova/Views/Catalog/StreamPickerView.swift`, `Nova/Views/Player/SubtitlePickerView.swift`.

- Quality, cached-only, source, size, and grouping controls now pass their selected value to the shared style and show checkmarks; selection remains visible when remote focus moves away.
- Filter expansion uses a chevron and its own selected state; “Filters On” separately reports whether filters are applied. VoiceOver gets both states.
- Custom capsule fills beneath focus surfaces were removed. Shared rounded controls now own fill, border, pointer hover, press, disabled, and remote-focus rendering.
- Stream titles, metadata, playback affordances, quality labels, and tvOS source/confidence badges use semantic foregrounds that remain readable on the white focus surface.
- Advanced filter choices use adaptive columns; compact and accessibility-size stream rows stack instead of squeezing a fixed quality column against long titles.
- The smart-filter clear button uses the shared icon control and minimum hit target; refresh and cancel actions opt into the shared chip surface.
- Subtitle choices and provider refresh now have one shared row surface; persistent checks and selected accessibility traits identify the active track. Titles and explanatory text wrap without fixed-height clipping.

Swift parse and whitespace checks passed for these refinements. Playback resolution, ranking, source filtering semantics, subtitle application, and provider calls are unchanged. Generic iOS/tvOS compilation is part of parent integration; physical-device visual/focus checks remain pending.

## VLC audio and subtitle follow-through

Additional scoped polish in `Nova/Views/Player/VLCPlayerView.swift`, `VLCPlayerModel.swift`, and the Foundation-only `Nova/Services/SubtitleSelectionPolicy.swift`:

- Audio, embedded/imported subtitle, and Off checkmarks read VLC's actual indices. The picker refreshes tracks when opened and after changes; provider selections are associated with confirmed VLC track IDs. An unknown index does not claim Off. Registration polling only publishes changed arrays/indices, avoiding identical player/picker rebuilds every 100 ms.
- External downloads show a pending spinner separately from the applied selection. Choosing Off, an embedded track, another provider, Done, dismissing the picker, or leaving playback retires pending download intent. An old completion cannot clear a newer spinner or announce a successful selection.
- External files register with `enforce: false`; Nova selects the registered track only if the original request is still current. Registration is serialized to associate new track IDs with the correct file. If VLC cannot expose one unambiguous new track within the bounded wait, Nova explains that state instead of guessing or declaring success.
- Non-success HTTP responses, empty files, native attachment errors, and unconfirmed selections have explicit recovery text. A file selected from Files is copied while security-scoped access is still active so asynchronous VLC reading has a stable local URL.
- Track choices share neutral rounded controls and readable focus colors, persistent checks, and selected accessibility traits. The picker has Done and cancel-download actions and exposes the sole audio track as well as multiple-track choices.
- Subtitle size shows a percentage on both platforms. The slider has a label/value; Apple TV smaller/larger buttons disable at exact 50%/250% limits. Persisted nonfinite or out-of-range values normalize before use by the preview/native renderer.

**21 additional native checks passed** in `scripts/SubtitleSelectionChecks.swift`: late completions after Off/dismissal, superseding language choices, stale finalizers, repeated completion/cancellation, malformed stored scale, and exact repeated-step limits. These verify the shared intent/scale policy, not native VLC registration or rendering. Source parse and whitespace checks passed; both-platform generic builds remain parent integration. Confirm native track registration, remote focus, and visual subtitle sizing on device.

The bundled VLCKit headers confirm `currentVideoSubTitleIndex` and `currentAudioTrackIndex` use -1 for no active track. Attachment behavior was checked against [VLCKit's media-player reference](https://videolan.videolan.me/VLCKit/interface_v_l_c_media_player.html) and [VideoLAN's LibVLC media-player API](https://videolan.videolan.me/vlc/master/group__libvlc__media__player.html). No personal media or subtitle-provider requests were made during verification.

Final integration: generic iOS and tvOS builds passed after the shared polish and platform-availability fixes. See [combined validation record](NOVA_30_IMPROVEMENTS_2026_09_14.md). No simulator or device execution was performed.
