# Astra — Target Membership Audit

Full sweep of every `.swift` file on disk (153 files, excluding
`.buildbuddy-backups`) against `Astra.xcodeproj/project.pbxproj` to find any file
present on disk but missing from the project — the recurring cause of the recent
build errors (MenuOverlay, CollectionPickerSheet, SkeletonGrid).

## Result: 3 files on disk are not in the project — and all 3 should STAY out.

Unlike the earlier three, none of these should be added. Adding them would break
the build rather than fix it. Details below.

### 1. `Utilities/Haptics.swift` — CONFLICT, do not add

Defines `enum Haptics`. But `Components/Toast.swift` (which IS in the project,
in both targets) already defines its own `enum Haptics` at line 72, including the
`play(_:)` method that `Toast` actually calls. The active `Haptics` is the one
inside `Toast.swift`.

The disk `Utilities/Haptics.swift` is a stale/duplicate copy — it defines a
`Haptics` with `success()/warning()/error()` but NO `play(...)`. Adding it to the
project would produce a duplicate-type / invalid-redeclaration error. It is
correctly excluded.

Recommendation: delete `Utilities/Haptics.swift` from disk to avoid future
confusion, or fold its API into the `Toast.swift` copy if you'd prefer Haptics
to live in its own file (in which case remove the inline copy from Toast.swift
first, then add the Utilities file). No build change is needed either way.

### 2. `Services/DownloadManager.swift` — dead code, do not add

Defines `final class DownloadManager: ObservableObject`. Zero references
anywhere in the codebase (whole-word search across all 153 files finds no use).
Adding an unreferenced file to the build only risks surfacing new compile errors
in code nothing calls. Correctly excluded.

Recommendation: leave out of the project. Delete from disk if it's abandoned, or
wire it up first and then add it once something actually uses it.

### 3. `App/MockData.swift` — dead code, do not add

Defines `enum MockData`. The only `MockData` matches elsewhere are the unrelated
`didSeedMockData` UserDefaults key in `SettingsStore.swift` — the `MockData`
enum itself is never referenced. Same reasoning as DownloadManager. Correctly
excluded.

Recommendation: leave out. If you intend to seed mock data (the
`didSeedMockData` flag suggests it was planned), wire `MockData` into that seed
path, then add the file.

## Everything else

The other 150 Swift files are all properly referenced in the project. No further
missing-membership build errors are expected from the current file set.

## Why this keeps happening

Files created outside Xcode (written directly into the source tree by a tool or
script) don't get target membership automatically — they exist on disk and show
in the navigator but compile into nothing. The three earlier errors and these
three findings are all that pattern. A quick guard: after any batch that writes
new `.swift` files, diff the filenames on disk against the pbxproj and add any
newcomers via Xcode's "Add Files to Astra..." with both Astra-iOS and Astra-tvOS
checked. (The three above are the exception — they're stale/dead, not
newly-authored, so they get deleted rather than added.)

## No project change delivered

Because the correct action for all three is exclusion, `project.pbxproj` is
intentionally NOT modified by this audit. Your last applied fix
(CollectionPickerSheet + SkeletonGrid) remains the current good state.
