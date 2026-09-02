# Nova UI and playback audit

Scope: all 184 Swift files, including 86 files under `Views` and `Components`, plus
all 54 sheet, full-screen-cover, and popover presentation sites.

## Changes completed

- Consolidated the visible application into one cinematic component system.
- Removed selectable legacy detail and player-overlay presentations.
- Added cancellation guards to progressive source discovery and stream resolution.
- Added progressive source counts, completion, skeletons, cancellation, and failover labels.
- Unified player accessory controls and exposed prepared next-episode playback.
- Preserved all local-first data, stream ranking, provider, playback, progress, and tracking contracts.

## Retained intentionally

- Plain button styles remain where the artwork itself is the semantic button or where
  native AVKit owns interaction. Replacing these mechanically would create nested
  surfaces and less native focus behavior.
- Fixed frames remain for posters, artwork, player controls, QR codes, and minimum tap
  targets. General page layout continues to use adaptive widths.
- Persisted legacy enum cases remain for backward decoding of existing preferences;
  they no longer select competing application presentations.
- Each sheet and cover keeps one state owner. Presentation modifiers were not hoisted
  when doing so would duplicate bindings or change navigation lifetime.

## Follow-up verification rule

Any future UI page must use Nova's shared state views, button families, glass surfaces,
typography, and focus treatments. New visual-style selectors require an explicit
product decision because the app now intentionally exposes one design language.

Run `python3 scripts/audit_cinematic_ui.py` with configuration and target validation.
The guard rejects stock bordered button treatments and live legacy-style branches
while reporting the current sheet, cover, and popover inventory.
