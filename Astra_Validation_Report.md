# Astra — Image & Rebrand Validation Report

Checked the re-uploaded `Astra.zip` (new artwork applied). **No problems found —
nothing needed changing.** The repo is icon/asset submission-ready.

## New artwork — all correct
- **iOS/iPadOS app icon:** all 14 sizes present at exact dimensions
  (1024, 180, 167, 152, 120, 87, 80, 76, 60, 58, 40, 29, 20), all square,
  all RGB with **no alpha channel** — passes Apple's "no transparency" rule.
- **tvOS app icon (layered):** front layers 400×240 / 800×480 are transparent
  (wordmark), back layers opaque (background). Correct parallax setup.
- **tvOS App Store icon (layered):** 1280×768 front transparent, back opaque. Correct.
- **Top Shelf:** 1920×720 & 3840×1440 (standard), 2320×720 & 4640×1440 (wide) —
  all exact.
- Every asset differs from the old Astra art, so the new design is in place
  across all slots.

## Rebrand integrity — still intact
- **0** residual `astra` references (any case) in file contents or names.
- Bundle IDs: `com.astra.app.ios`, `com.astra.app.tvos`, `com.astra.app.ios.widgets`.
- pbxproj `INFOPLIST_FILE` / `CODE_SIGN_ENTITLEMENTS` references: **0 missing** —
  all resolve on disk.
- 152 Swift files, 36 asset `Contents.json` files intact.

## Before you archive/submit
1. Run `fix_icons.sh` at the repo root (keeps the tvOS `primary-app-icon` role
   correct and purges any stray App Store imagestack).
2. Build to a device + tvOS: confirm the icon renders at the smallest iOS sizes
   and the tvOS layers separate with parallax on focus.
3. Reminder (outside the code): new bundle IDs + `group.com.astra.shared` still
   need registering in the Apple Developer portal with fresh provisioning
   profiles, and the `astra-ai-worker` still needs `wrangler deploy` + its new
   URL pasted into the app's AI settings.
