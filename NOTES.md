# Astra — MenuOverlay build fix

## What was wrong

The three errors on `RootView` were one root cause:

    Cannot find 'MenuOverlay' in scope
    Type '()' cannot conform to 'View'
    Missing argument for parameter #1 in call

`MenuOverlay.swift` existed on disk and was correct — but it was **not a member
of any target**. In `Astra.xcodeproj/project.pbxproj` it had no
`PBXFileReference`, no group entry, and no entry in any `Sources` build phase.
So the compiler never saw `MenuOverlay` (or `MenuButton`, defined in the same
file), and every use in `RootView` failed. The `Type '()' cannot conform to
'View'` and `Missing argument` errors were cascades from that missing type, not
separate bugs.

By contrast `TVMenuOverlay.swift` and `RootView.swift` were correctly compiled
into both the Astra-iOS and Astra-tvOS targets — which is why only MenuOverlay
was missing.

## What was changed

Only `Astra.xcodeproj/project.pbxproj` was edited. `MenuOverlay.swift` was added
to the project with:

- a `PBXFileReference` (new GUID `3942CEEC0089118857658DE6`)
- a child entry in the `Views` group (so it now appears in the navigator)
- a `Sources` build-file entry in **Astra-iOS** (phase `DD00A89A…`)
- a `Sources` build-file entry in **Astra-tvOS** (phase `C71A22D7…`)

No Swift source was modified — `MenuOverlay.swift` is included here only for
reference. `TVMenuOverlay.swift`, `RootView.swift`, and everything else are
untouched.

Verified after patching: brace/paren balance intact; the new file reference and
both build-file GUIDs resolve; each Sources phase points at the correct target.

## How to apply

Replace your project file with the corrected one:

    cp Astra.xcodeproj/project.pbxproj /Users/owens/Documents/Astra/Astra.xcodeproj/project.pbxproj

Then in Xcode: Product -> Clean Build Folder (Shift-Cmd-K), build. The three
issues should be gone and `MenuOverlay.swift` will now show under Views.

If instead you'd rather fix it by hand in Xcode: select `MenuOverlay.swift` in
the navigator, open the File Inspector (right panel), and under **Target
Membership** tick both **Astra-iOS** and **Astra-tvOS**. That does the same thing
this patch does.

## Commit so it sticks

    git -C /Users/owens/Documents/Astra add Astra.xcodeproj/project.pbxproj
    git -C /Users/owens/Documents/Astra commit -F - <<'MSG'
    Add MenuOverlay.swift to Astra-iOS and Astra-tvOS targets
    MSG
