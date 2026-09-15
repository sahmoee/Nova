# Nova: September 14 features and expanded polish

Nova joins Stocked, The Sesh, and AppPulse in the ten-feature/twenty-polish pass. The later request expands Nova's selection, shapes, hover, menus, and accessibility work beyond that baseline. This record describes implemented behavior rather than proposed features.

## Ten features

| # | Feature | Entry point |
|---|---|---|
| 1 | Named, ordered Watch Night plans | Library → Watch Night → New plan |
| 2 | Find a title that fits the available time | Watch Night → Find a title that fits |
| 3 | Compare two or three viewing choices | Watch Night → Compare titles |
| 4 | Private, spoiler-protected viewing notes | Watch Night → Private viewing notes |
| 5 | Start, break, and estimated finish scheduling | A watch plan → Schedule |
| 6 | Reviewed portable plan JSON import/export | Watch Night → Import; a plan → Export (iOS) or View JSON (tvOS) |
| 7 | Search/filter/sort Sonarr series | Settings → Sources/Library → Sonarr → Series |
| 8 | Per-series file availability details | Sonarr → Series → select a title |
| 9 | Grouped calendar with date, monitoring, and availability filters | Sonarr → Calendar |
| 10 | Queue records with progress, sizes, estimates, and warning details | Sonarr → Queue → select a record |

See [Watch Night](WATCH_NIGHT_2026_09_14.md) for its six features and ten individually documented polish changes. See [Sources](NOVA_SOURCE_IMPROVEMENTS_2026_09_14.md) for the remaining four features and ten polish changes. Those two manifests form the requested 10 + 20 baseline.

## Expanded Nova polish

### Shared controls and artwork

- `Theme.Radius` distinguishes poster, card, chip, icon, and navigation geometry; `Theme.Control` defines consistent press/focus movement and outlines.
- Persistent selection is separate from keyboard/remote focus, pointer hover, and prominence. Selected controls expose accessibility state and retain a border after focus moves away.
- tvOS controls use neutral glass, bright white focus, and semantic dark labels. iOS keeps system-blue actions and selection. No artwork-derived chrome tint or accent glow is introduced.
- Reduce Motion suppresses lift; Reduce Transparency supplies opaque surfaces; Increased Contrast strengthens borders. Disabled controls dim once and ignore focus/hover activation.
- iOS pointer hover is restrained and does not enlarge neighboring rows. Icon controls are circular with usable minimum hit targets. Button padding no longer doubles the shared minimum height.
- Media-card focus preserves artwork colors; catalog wrappers use artwork-specific styles rather than filled row styles. Horizontal rails allow the focus frame to extend beyond the scroll clipping boundary.
- Media/catalog titles reserve two lines consistently. Detail-opening and direct-play cards show different icons and accessibility hints.
- Continue Watching uses 16:9 artwork; its resume badge moves with the artwork, and remaining-time formatting rejects invalid/overflowing values. Quality badges stay within artwork bounds.
- Source cards follow their owning link's focus, use neutral shadows, and wrap long titles/status labels.

### Navigation, settings, and title details

- The iPhone home bar has a persistent rounded selection surface, outline, pointer feedback, larger-text wrapping, and accurate reselect accessibility hints.
- Floating menus use shared panel/item radii, a visible current-page checkmark, and reduced-transparency fallback. Menu transitions respect Reduce Motion.
- Settings group identities remain stable across updates; rows have visible press/hover feedback without a second nested card. Search dismisses the keyboard during scrolling and has a usable clear target.
- Settings values wrap at larger text sizes; menu pickers stack vertically when necessary. Group backgrounds honor Reduce Transparency, and tvOS focus is not clipped to a containing group.
- Apple TV Settings has a direct Accessibility destination. System motion, transparency, and contrast preferences are reported from actual environment values; the iOS text-size slider has a spoken label/value.
- TV setting toggles highlight the entire row and show On/Off plus a check symbol. Source-priority arrows have usable hit targets and specific accessibility labels.
- Title-detail Play, watched, season, and secondary actions use one shared surface. Watched and season selection remain visibly and accessibly identified. Episode titles have consistent two-line space.
- Explicit Library deletion also removes this device's Watch Night plans/private notes, including corrupt saved data. An error stops the reset before its library deletion phase; undo/drafts cannot revive erased Watch Night data.

### Search and playback pickers

- New & Hot filters show their selected state without white text on a white focused surface.
- Smart Search, catalog, folder, and download actions have one correctly padded shared surface. Poster results use artwork styles, and icon-only actions use circular controls.
- Stream quality, cache, source, size, and grouping filters pass real selection into shared styles and show checks. Expanded/applied-filter states are separately reported.
- Stream metadata and badges use semantic foregrounds on tvOS; narrow and larger-text rows stack, while filter choices wrap in adaptive columns.
- Subtitle selection uses a single row surface with a persistent checkmark and selected accessibility trait. Provider refresh, cancel, and clear actions use shared controls.
- VLC's audio/subtitle picker reads the engine's current track IDs. Pending downloads have their own progress state; only an applied track gets a selection check. Off, another track, dismissal, and leaving playback invalidate older subtitle requests.
- External subtitles register without forcing native selection. Registration is serialized, then the current request selects and confirms the registered track. Local imported files are copied while their security-scoped access is active. Unchanged registration samples do not repeatedly publish view state.
- Subtitle sizing is finite, bounded, rounded, spoken as a percentage, and disables stepping at either limit. Native registration/rendering remains a device acceptance check.

## Ownership and compatibility

Nova owns these changes. Both iOS and tvOS consume the shared views and new policies; no Worker, Jarvis service, site, provider database, or released API contract changes are required. Existing Library/Tracker records and credentials retain their owners. Sonarr remains optional and read-only; the queue explicitly reports its existing first-page limit.

Watch Night is device-local, protected, atomic storage. Private notes never enter portable plans, setup snapshots, or iCloud mirrors. Imported plans are previewed and matched conservatively; unknown durations never produce a falsely precise finish time. Rollback can leave the additive Watch Night file intact; only an explicit local reset removes it.

## Validation

- Watch Night: 37 native policy checks passed.
- Sonarr: 40 native policy checks passed.
- Subtitle request ordering and scale: 21 native policy checks passed. These test the ordering/normalization policy, not live VLC attachment.
- **Final generic iOS and tvOS builds passed** with `CODE_SIGNING_ALLOWED=NO`, using the existing external DerivedData cache. No simulator runtimes were used.
- Built metadata: Nova.app: version 1.7, build 172; Nova-tvOS.app: version 1.7, build 171.
- Build logs: `/tmp/nova-improvements-ios-final-20260914.log` and `/tmp/nova-improvements-tvos-final-20260914.log`.
- Existing `UnifiedQAReporter` actor-isolation and AMSMB2 Makefile resource warnings remain; no new build error remains.
- Source parsing and whitespace checks passed for the implemented batches.
- No simulator, physical-device visual run, personal-data deletion, or request to personal Sonarr/media servers was used for validation. Device focus/hover/layout review and real-provider acceptance remain separate from compilation; a build does not establish pixel-for-pixel parity with Apple TV.
