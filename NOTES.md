# Astra — LibraryView build fix

## What was wrong

All three errors on `LibraryView` were one root cause:

    The compiler is unable to type-check this expression in reasonable time
    Cannot find 'CollectionPickerSheet' in scope
    Cannot find 'SkeletonGrid' in scope

`CollectionPickerSheet.swift` (in Views/Library) and `SkeletonGrid.swift` (in
Components) existed on disk and were correct — but neither was a member of any
target. In `Astra.xcodeproj/project.pbxproj` they had no `PBXFileReference`, no
group entry, and no entry in any `Sources` build phase, so the compiler never
saw the two types.

The "unable to type-check in reasonable time" error was a **cascade**, not a
real complexity problem: when a view body references undefined types, the Swift
type-checker loses the type information it needs and falls back to an expensive,
ultimately failing inference pass. With the two types resolved it clears.

This is the same class of issue as the earlier `MenuOverlay` fix — files present
on disk but never added to the project.

## What was changed

Only `Astra.xcodeproj/project.pbxproj` was edited. Both files were added to the
**Astra-iOS** and **Astra-tvOS** targets, each with a file reference, its group
child entry (Library / Components), and a Sources build-file entry in both
targets. No Swift source was modified; the two `.swift` files are included here
only for reference.

Verified after patching: brace/paren balance intact; new file references and all
four build-file GUIDs resolve; each entry sits in the correct target's Sources
phase.

## How to apply

    cp Astra.xcodeproj/project.pbxproj /Users/owens/Documents/Astra/Astra.xcodeproj/project.pbxproj

Then in Xcode: Product -> Clean Build Folder (Shift-Cmd-K), build. All three
issues should clear and both files will appear under their groups.

Manual alternative: select each file in the navigator, open the File Inspector,
and tick both **Astra-iOS** and **Astra-tvOS** under Target Membership.

## Commit so it sticks

    git -C /Users/owens/Documents/Astra add Astra.xcodeproj/project.pbxproj
    git -C /Users/owens/Documents/Astra commit -F - <<'MSG'
    Add CollectionPickerSheet and SkeletonGrid to Astra-iOS and Astra-tvOS targets
    MSG

## Pattern worth noting

Three of your recent Astra errors (MenuOverlay, and now these two) were all
"file on disk, not in project." If files are being created outside Xcode (e.g.
by a tool or script writing directly to Views/), they won't get target
membership automatically. Adding them via Xcode's "Add Files to Astra..." with
both targets checked, or running a membership check after such writes, would
prevent the recurrence.
