# Nova for Mac

Nova-Mac is a Mac Catalyst scheme sharing Nova's iPad/SwiftUI application, library,
settings, navigation and network integrations. It keeps the existing iOS and tvOS
products and their minimum OS requirements unchanged. The Mac build supports
macOS 15 or later (Catalyst 18 deployment target); build on Xcode 26.3 or later.

```
xcodebuild -project Nova.xcodeproj -scheme Nova-Mac \
  -destination 'platform=macOS,variant=Mac Catalyst,arch=x86_64' \
  -derivedDataPath /path/to/internal/build-directory CODE_SIGNING_ALLOWED=NO build
```

Use the shared scheme so the existing automatic QA build reservation and stamp
run. Marketing version stays manual. The Mac bundle identifier is
`com.nova.app.mac`; iOS remains `com.nova.app.ios`.

## Platform boundaries

- This build uses AVPlayer for Apple-compatible MP4, MOV and HLS sources. The
  pinned VLCKit 3.6.0 XCFramework contains native macOS, iOS and tvOS slices but
  **no Mac Catalyst slice**. VLC engine choices/recovery are not offered on Mac;
  failed playback shows an explicit format explanation. AVPlayer probes actual
  content even for extensionless or server-transcoded URLs. Existing iOS/tvOS VLC
  playback is unchanged. A separately installed player may play those formats;
  this build does not install an external player.
- Apple Intelligence is unavailable in this Mac build. Existing deterministic
  parsers and optional server AI remain the fallbacks. Live Activities are an
  iOS-only implementation. Mac does not expose in-app QA.
- Mac reuses the wide sidebar composition; haptics, embedded widgets, QR scanning
  and pull-to-refresh are not advertised as Mac capabilities.
- Local ad-hoc signing does not provision Apple push or iCloud capabilities.
  Cloud signing/distribution needs a separately provisioned developer build.
  No credentials or local NovaConfig.json belong in the application artifact.

## Shared dependency provenance

`Packages/SowensKit` was restored from Nova's own preserved PR #2 checkout
(`codex/portfolio-refinement`), which contained the dependency already referenced
by the project. Its manifest, sources, tests and reference snapshots are versioned
here so another checkout can reproduce the build. Generated `.swiftpm` and build
caches stay ignored. No unrelated PR changes were merged.
