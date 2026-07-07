# Astra — Bundle ID Guard + WidgetKit note

Two things from the screenshot: the Astra bundle identifier reverting, and the
red WidgetKit reference.

## 1. Bundle identifier keeps reverting

Astra's General tab shows `com.frametv.app.ios` — the FrameTV repo's id, not
Astra's. It "reverts" because Xcode stores `PRODUCT_BUNDLE_IDENTIFIER` **per
build configuration** (Debug / Release / etc.), not once. The General tab shows
only the selected config, so if one config disagrees the value snaps back when
you switch config, build, or reopen. Root causes, in order:

1. **Per-config mismatch** — Debug and Release hold different ids (most common).
2. **Duplicated target** — a target copied from FrameTV inherited its id.
3. **.xcconfig override** — an xcconfig sets the id and wins over the General tab.
4. **Committed pbxproj** — you change it in Xcode but don't commit, then a branch
   switch / `git checkout` restores the old value. Looks identical to a revert.

### Fix — run the guard

`bundleid-guard.sh` is read-only until you ask it to write.

```
# Audit: shows every id in the project + flags mismatches, xcconfig overrides,
# and uncommitted pbxproj state. Auto-finds Astra.xcodeproj if run beside it.
./bundleid-guard.sh --project /Users/owens/Documents/Astra/Astra.xcodeproj

# Preview pinning Astra to its correct id (writes nothing):
./bundleid-guard.sh --project .../Astra.xcodeproj --set com.astra.app.ios

# Apply it across all configs (makes a .bak first):
./bundleid-guard.sh --project .../Astra.xcodeproj --set com.astra.app.ios --apply
```

Pick the actual id you want for Astra — `com.astra.app.ios` is just a sensible
guess mirroring the FrameTV pattern. If the widget extension needs its own id
(it must be `<app-id>.SomeSuffix`, e.g. `com.astra.app.ios.AstraWidgets`), set
the main app first, then fix the extension's line by hand — see the audit output
for exactly which lines exist.

### Make the fix stick

After `--apply`, **commit project.pbxproj immediately**. An uncommitted change
is the #1 way this silently reverts on the next checkout:

```
git -C /Users/owens/Documents/Astra add Astra.xcodeproj/project.pbxproj
git -C /Users/owens/Documents/Astra commit -F - <<'MSG'
Pin bundle identifier to com.astra.app.ios across all configs
MSG
```

(`-F` matches your CommitSafety habit — no shell metacharacters in the message.)

## 2. Why WidgetKit is red

WidgetKit is Apple's system framework for Home Screen / Lock Screen / StandBy
widgets and Live Activities — it's what `AstraWidgetsExtension` is built on.

It's **red** because the file reference is broken: Xcode has a reference to
WidgetKit but can't find it at the recorded path. Red = "referenced, not found."
SwiftUI right below it is normal, so it's specifically WidgetKit's link that's
dangling. Usual causes: the framework was linked from a specific/older SDK path
that moved, or added by absolute path instead of resolved from the current SDK.

### Fix

1. Select the red **WidgetKit** in the Frameworks group and delete the reference
   (Remove Reference — this does not delete anything on disk).
2. Select the target that needs it (the widgets extension) →
   **General → Frameworks, Libraries, and Embedded Content** (or
   **Build Phases → Link Binary With Libraries**) → **+** → add
   **WidgetKit.framework**, letting Xcode resolve it from the SDK.
3. As a system framework it should be **Do Not Embed**.

A red system framework won't always break the build if it's still linked
elsewhere, but clean it up so it isn't hiding a real linkage problem.
