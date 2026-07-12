# Astra icons — why Xcode still shows Astra, and how to fix it

## Diagnosis
The icon files on disk are correct. I verified every size in
`Assets-iOS.xcassets/AppIcon.appiconset` (20, 29, 40, 58, 60, 76, 80, 87, 120,
152, 167, 180, 1024) plus the tvOS layered icons and Top Shelf — each one is a
pixel-exact copy of the new Astra constellation art (measured distance 0.0 from
the new 1024 master, and far from the old Astra art). `Contents.json`
references the right filenames and there are no leftover old PNGs.

So what you're seeing in Xcode is a **stale cache**, not a file problem. When the
PNGs are replaced on disk while Xcode is open (e.g. BuildBuddy dropping them in),
Xcode keeps showing the old thumbnails and — worse — keeps building the old
compiled `Assets.car` from DerivedData, so the installed app also shows the old
icon. The title bar showing "Finished running Astra on Key" is the giveaway: it
ran with the cached asset catalog.

## Fix (either run the script, or do these by hand)
1. Quit Xcode completely.
2. Delete this app's DerivedData (that's where the old compiled icons live).
3. Clear Xcode's asset/thumbnail caches.
4. Delete the Astra app from the device/simulator "Key" (iOS caches the launcher
   icon under the bundle; a fresh install re-reads it — and since the bundle ID
   changed to com.astra.app.*, it's effectively new anyway).
5. Reopen Xcode → Product → Clean Build Folder (Shift-Cmd-K) → build & run.

The included `clear_icon_cache.sh` does steps 1-3 automatically. Run it, then do
4 and 5.

## If it STILL shows Astra after that
Then the checkout Xcode has open is not the one with the new icons. Confirm the
folder Xcode's title bar points to is the same repo you zipped, and that the
new PNGs are actually present at
`Astra/Resources/Assets-iOS.xcassets/AppIcon.appiconset/`.
