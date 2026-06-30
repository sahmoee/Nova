# FrameTV Top Shelf — Xcode Setup (tvOS)

Top Shelf shows Continue Watching and Recently Added rows on the Apple TV home screen,
above the FrameTV icon. Like widgets, it needs a **new Xcode target** that can't be
created from outside Xcode. One-time setup, ~5 minutes.

It reuses the **same App Group snapshot** the app already writes for widgets, so there's
no extra app-side data work.

---

## What's already done (in the zip)

- `FrameTVTopShelf/FrameTVTopShelf.swift` — the Top Shelf content provider.
- `FrameTVTopShelf/FrameTVTopShelf.entitlements` — App Group entitlement.
- `FrameTVTopShelf/Info.plist` — extension Info.plist (principal class + extension point).
- The app already writes the shared snapshot (`WidgetShared`) on tvOS too.
- The App Group `group.com.frametv.shared` is already in the app entitlements.

---

## Step 1 — Create the TV Top Shelf target

1. **File ▸ New ▸ Target…**
2. Select the **tvOS** tab, choose **TV Top Shelf Extension**. **Next**.
3. Product Name: **FrameTVTopShelf** (match the folder name).
4. Team: `5DV5N49VG8`. **Finish**.
5. "Activate scheme?" → **Cancel** (keep the app scheme active).

Xcode creates a `FrameTVTopShelf` group with a template `ContentProvider.swift` and an
`Info.plist`.

## Step 2 — Replace the template with the zip's file

1. **Delete** the template `ContentProvider.swift` (or `FrameTVTopShelf.swift`) Xcode made.
2. **Add** the zip's `FrameTVTopShelf/FrameTVTopShelf.swift` to the **FrameTVTopShelf** target.
3. Make sure the zip's **Info.plist** keys are present in the target's Info.plist —
   specifically `NSExtensionPrincipalClass` = `$(PRODUCT_MODULE_NAME).ContentProvider` and
   `NSExtensionPointIdentifier` = `com.apple.tv-top-shelf`. Copy from the zip's Info.plist
   if Xcode's generated one differs.

## Step 3 — Share WidgetShared.swift with this target

1. Select **`FrameTV/App/WidgetShared.swift`**.
2. File Inspector ▸ **Target Membership** ▸ check **FrameTVTopShelf** (in addition to the
   app and the widget target it's already on).

The Top Shelf reads the same snapshot model the app writes.

## Step 4 — Enable the App Group on the Top Shelf target

1. FrameTVTopShelf target ▸ **Signing & Capabilities**.
2. **+ Capability ▸ App Groups** (if not present).
3. Check **`group.com.frametv.shared`** (the same group the tvOS app uses).

## Step 5 — Point the target at its entitlements (if needed)

1. FrameTVTopShelf ▸ Build Settings ▸ "Code Signing Entitlements".
2. Ensure it's `FrameTVTopShelf/FrameTVTopShelf.entitlements`.

## Step 6 — Build & run on Apple TV

1. Run the **tvOS app** scheme on an Apple TV / simulator.
2. Open the app once so it writes a snapshot (add or play something if empty).
3. Go to the tvOS home screen, move focus to the **top row** while FrameTV is the focused
   app — the Continue Watching / Recently Added rows appear.
4. Selecting an item opens FrameTV to that title via the deep links already in the app.

---

## IMPORTANT — verify the TVServices API at build time

The Top Shelf provider uses the modern sectioned-content API (`TVTopShelfSectionedContent`,
`TVTopShelfItemCollection`, `TVTopShelfSectionedItem`, `TVTopShelfAction`). These were written
without a tvOS compiler available, so **if Xcode reports an error on any of these symbols**, it's
almost certainly a minor signature difference (Apple has revised these APIs over tvOS versions).
If that happens, send me the exact error and I'll correct the call — the structure (read the
snapshot, build two sections, attach a deep-link action per item) is right; only a method name or
argument label may need adjusting.

## Troubleshooting

- **No rows appear** → open the app once so it writes the snapshot; confirm the App Group string
  matches on the app and the Top Shelf target.
- **"WidgetShared not found"** → Step 3 wasn't applied; add it to the Top Shelf target membership.
- **App Group container nil** → group not enabled on the Top Shelf target, or name mismatch.
- **Items show but don't open the app** → confirm the app builds with the deep-link scheme
  (`frametv://`) registered (it is, from the deep-links step).
