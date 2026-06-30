# FrameTV Widgets — Xcode Setup

The widget code is in the zip, but widgets require a **new Xcode target** that I can't
create from outside Xcode. These are the one-time steps. They take about 5 minutes.

After this, you won't need to repeat any of it — future widget changes are just code.

---

## What's already done (in the zip)

- `FrameTV/App/WidgetShared.swift` — shared data model, **already added to the app target**.
- `FrameTVWidgets/FrameTVWidgets.swift` — the widget UI (Continue Watching, Recently Added).
- `FrameTVWidgets/FrameTVWidgets.entitlements` — widget entitlements with the App Group.
- `FrameTVWidgets/Info.plist` — widget extension Info.plist.
- The app's entitlements now include the App Group `group.com.frametv.shared`.
- The app already writes the widget snapshot whenever the library changes.

---

## Step 1 — Create the Widget Extension target

1. In Xcode: **File ▸ New ▸ Target…**
2. Choose **Widget Extension** (under iOS). Click **Next**.
3. Product Name: **FrameTVWidgets** (must match the folder name).
4. **Uncheck** "Include Configuration App Intent" (these are static widgets).
5. Team: your team (`5DV5N49VG8`). Click **Finish**.
6. When asked "Activate scheme?", click **Cancel** (keep the app scheme active).

Xcode creates a `FrameTVWidgets` group with a template `FrameTVWidgets.swift` and an
`Assets`/`Info.plist`.

## Step 2 — Replace the template files with the ones from the zip

1. **Delete** the template `FrameTVWidgets.swift` Xcode generated (Move to Trash).
2. **Add** the zip's `FrameTVWidgets/FrameTVWidgets.swift` to the FrameTVWidgets target
   (drag it in, or File ▸ Add Files; make sure only the **FrameTVWidgets** target is checked).
3. Do the same for `FrameTVWidgets/Info.plist` and `FrameTVWidgets/FrameTVWidgets.entitlements`
   if Xcode's generated ones differ — or just copy the App Group / NSExtension keys from the
   zip's versions into Xcode's generated ones.

## Step 3 — Share WidgetShared.swift with the widget target

1. Select **`FrameTV/App/WidgetShared.swift`** in the navigator.
2. Open the **File Inspector** (right panel).
3. Under **Target Membership**, check **BOTH**:
   - `FrameTV` (the app) — already checked
   - `FrameTVWidgets` (the extension)

This is the key step: the widget reads the same model the app writes.

## Step 4 — Enable the App Group on BOTH targets

For **each** of the `FrameTV` app target and the `FrameTVWidgets` target:

1. Select the target ▸ **Signing & Capabilities**.
2. If "App Groups" isn't listed, click **+ Capability** and add **App Groups**.
3. Add (or check) the group: **`group.com.frametv.shared`**.

If Xcode shows the group with a warning, click the refresh/register button so it
registers the App Group in your Developer account. Both targets must show the **same**
group checked.

## Step 5 — Point the widget target at its entitlements (if needed)

1. FrameTVWidgets target ▸ **Build Settings** ▸ search "Code Signing Entitlements".
2. Ensure it points to `FrameTVWidgets/FrameTVWidgets.entitlements`.

## Step 6 — Build & run

1. Build the **app** scheme (not the widget scheme) and run on a device/simulator.
2. Open the app once so it writes a snapshot (add or play something if your library is empty).
3. Long-press the home screen ▸ **+** ▸ search **FrameTV** ▸ add **Continue Watching** or
   **Recently Added**.
4. Tapping a poster opens FrameTV to that title (via the deep links already in the app).

---

## Troubleshooting

- **Widget shows "Nothing here yet"** → open the app once so it writes the snapshot; make
  sure the App Group string matches **exactly** on both targets and in `WidgetShared.swift`.
- **Build error "No such module 'WidgetKit'"** in WidgetShared → that file guards WidgetKit
  with `#if os(iOS)`, so this only happens if it was added to the tvOS target. WidgetShared
  should be on the **app** and **widget** targets only.
- **"WidgetShared not found" in the widget** → Step 3 wasn't applied; add WidgetShared to the
  widget target's membership.
- **App Group container is nil** → the group isn't enabled on the running target, or the name
  differs. Re-check Step 4.

If you change the App Group name, update it in **three** places: both targets' capabilities
and the `appGroup` constant in `WidgetShared.swift`.
