# Nova for Mac

Nova for Mac is a native macOS app (target `Nova-macOS`, scheme `Nova-Mac`), not
Mac Catalyst. It shares Nova's SwiftUI sources with iOS and tvOS and uses the
regular-width (iPad-style) sidebar composition. It supports macOS 15 or later and
builds on Xcode 26.3 or later. Mac Catalyst is no longer enabled on the iOS target.

```
xcodebuild -project Nova.xcodeproj -scheme Nova-Mac \
  -destination 'platform=macOS,arch=x86_64' \
  -derivedDataPath /path/to/internal/build-directory CODE_SIGNING_ALLOWED=NO build
```

Use the shared scheme so the automatic QA build reservation and stamp run.
Marketing version stays manual. The Mac bundle identifier is `com.nova.app.mac`;
iOS remains `com.nova.app.ios`. Entitlements: `Nova/Resources/Nova-macOS.entitlements`
(App Sandbox, network client/server, user-selected and Downloads files, calendars,
the shared iCloud container and app group). Info: `Nova/Resources/Info-macOS.plist`.

## Platform boundaries

- Playback offers both engines. AVPlayer runs in AppKit's `AVPlayerView` with
  native controls and Picture in Picture; VLCKit's macOS slice handles MKV, AVI and
  other formats through an `NSView` surface. Engine choice works as on iOS.
- Full-screen covers open as large resizable sheets (`novaFullScreenCover`).
- iOS-only modifiers used by shared screens have Mac stand-ins in
  `Nova/App/MacCompatibility.swift`; shared aliases live in `PlatformSupport.swift`.
- Sports providers open in the default browser. Episode air dates can be added to
  Calendar.
- Not on Mac: Apple Intelligence (on-device AI), Live Activities, CarPlay, Home
  screen quick actions, external player hand-off, in-app QA, haptics and
  pull-to-refresh.
- Local ad-hoc signing does not provision push or iCloud. Distribution needs a
  provisioned developer build. No credentials or local NovaConfig.json belong in
  the application artifact.

## Shared dependency provenance

`Packages/SowensKit` was restored from Nova's own preserved PR #2 checkout
(`codex/portfolio-refinement`), which contained the dependency already referenced
by the project. Its manifest, sources, tests and reference snapshots are versioned
here so another checkout can reproduce the build. Generated `.swiftpm` and build
caches stay ignored. No unrelated PR changes were merged.
