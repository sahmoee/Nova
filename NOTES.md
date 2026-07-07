# Astra — Bundle ID Rename (off com.frametv)

## What your audit actually revealed

Nothing is randomly reverting. The three ids are **consistent** — 2x each is
just Debug + Release agreeing per target:

    com.frametv.app.ios          -> iOS app
    com.frametv.app.ios.widgets  -> widget extension (nested under the app id)
    com.frametv.app.tvos         -> tvOS app

They're all wrong the same way: Astra was cloned from FrameTV and the bundle ids
were never renamed. That's why it "looked like" FrameTV in the General tab —
it literally is FrameTV's identifier, stably.

Because the widget id must stay a **child** of the app id, the earlier guard's
`--set` (one id everywhere) would break the extension. This script does an exact
per-target swap that keeps the nesting.

## Run it

```
# Preview (writes nothing):
/Users/owens/Documents/Astra/astra-rename-bundleids.sh

# Apply the default rename to the com.astra.app prefix (makes a .bak):
/Users/owens/Documents/Astra/astra-rename-bundleids.sh --apply

# Or choose your own prefix:
/Users/owens/Documents/Astra/astra-rename-bundleids.sh --prefix com.yourco.astra --apply
```

Default result:

    com.frametv.app.ios          -> com.astra.app.ios
    com.frametv.app.ios.widgets  -> com.astra.app.ios.widgets
    com.frametv.app.tvos         -> com.astra.app.tvos

Pick the prefix you actually want before applying — `com.astra.app` is a
placeholder mirroring the old pattern.

## Make it stick

After `--apply`, reopen Astra, confirm each target's id in General, then commit
the pbxproj so a checkout can't undo it:

```
git -C /Users/owens/Documents/Astra add Astra.xcodeproj/project.pbxproj
git -C /Users/owens/Documents/Astra commit -F - <<'MSG'
Rename bundle identifiers from com.frametv to com.astra.app
MSG
```

(`-F` keeps the message free of shell metacharacters, per CommitSafety.)

## If these ids are already registered

If you've made App IDs / provisioning profiles or App Store Connect records
under the old com.frametv ids, renaming means creating new App IDs for the new
identifiers and regenerating profiles. If the app was never shipped under the
frametv ids, there's nothing else to update.
