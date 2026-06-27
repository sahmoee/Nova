# FrameTV

A polished, native **Apple TV (tvOS)** and **iPhone/iPad (iOS/iPadOS)** media hub for watching
video you own, control, or are authorized to access. FrameTV is a *player*, not a content catalog —
there is no built-in library of media, no search engine, no scraper, and no source list. You bring
your own sources; FrameTV gives them a beautiful, focus-friendly living-room interface.

Built with SwiftUI, AVKit, and async/await. State persists locally; secrets live in the Keychain.

---

## What's in this build (Phase 1 + Phase 2)

**Phase 1 — Foundation & UI shell**
- App scaffolding for tvOS and iOS targets sharing one codebase.
- Design system (dark, cinematic theme) with reusable focusable components.
- Home dashboard, Library with filters, Sources hub, and full Settings.
- Local Codable JSON persistence for the library; Keychain wrapper for secrets.
- Source-management UI for SMB shares, Real-Debrid, Direct URL, and Magnet links.
- Sample public-domain content seeded on first run so the UI is never empty.

**Phase 2 — Playback core**
- AVKit-based player with a clean full-screen experience.
- Resume support: items more than 30 seconds in (and under 90% complete) resume where you left off.
- Progress is saved every 10 seconds during playback and on exit.
- Items are marked watched at 90% and leave Continue Watching.
- Playback error state with retry.
- The **Direct URL** flow is fully working end to end: paste a link, validate it, add it to the
  library, and play immediately.

**Phase 3 — Metadata, addons & advanced playback**
- **Discover** tab: search movies and shows by title (via your own TMDB API key) and open a detail
  screen with artwork, overview, and—for shows—a full season/episode list.
- **Stremio-protocol addons**: install any addon by its manifest URL to find streams. Quick-add
  presets for **AIOStreams** and **Comet** prefill the flow (you supply your own configured instance
  URL). FrameTV ships no addons and recommends none; everything is user-supplied.
- **Stream picker** with quality, size, seeders, source, and a cached/instant badge, plus optional
  auto-select of the best stream by your preferred resolution.
- **Real-Debrid resolution**: torrent streams are resolved through *your own* Real-Debrid account
  (add magnet, select file, unrestrict). FrameTV never downloads or seeds torrents itself.
- **Subtitles**: from addons that expose them and from OpenSubtitles (with your key). SRT is
  converted to WebVTT for sideloading; a picker lets you switch tracks or turn them off.
- **Trakt**: connect via the TV-friendly device-code flow to see your watchlist and scrobble
  watched progress (start/pause/stop).
- **Player upgrades**: auto-play next episode, Skip Intro / Skip Outro controls (with optional
  auto-skip intro), a Subtitles menu, and seamless episode-to-episode continuation.
- **Credentials**: enter TMDB / Trakt / OpenSubtitles keys in Settings ▸ Metadata & Accounts
  (stored in the Keychain), or drop a `FrameTVConfig.json` fallback file (see `FrameTVConfig.example.json`).

The Real-Debrid and Magnet flows have complete networking and UI; they go fully live once you add
your own Real-Debrid token (Settings ▸ Real-Debrid). SMB browsing runs against a built-in mock
provider in this build — see **Roadmap** for the real SMB integration step.

---

## Requirements

- **Xcode 15.2** or newer.
- **tvOS 17** / **iOS 17** deployment targets (adjustable in target settings).
- An Apple Developer account only if you want to run on a physical Apple TV (simulator needs none).

---

## Opening and running

1. Open **FrameTV.xcodeproj** in Xcode.
2. Two schemes are included:
   - **FrameTV-tvOS** — the primary Apple TV app.
   - **FrameTV-iOS** — the iPhone/iPad build.
3. Pick the **FrameTV-tvOS** scheme and an **Apple TV** simulator (for example, Apple TV 4K), then press
   Run. The app launches with a few public-domain sample videos already in the library so you can
   try playback, resume, and the Direct URL flow right away.

No third-party packages are required to build this phase — it compiles and runs as-is.

---

## Adding the real SMB library (Roadmap, Phase 5)

Real SMB streaming uses the open-source **AMSMB2** package. When you're ready:

1. In Xcode: **File ▸ Add Package Dependencies…**
2. Enter the package URL: https://github.com/amosavian/AMSMB2
3. Add the **AMSMB2** product to the **FrameTV-tvOS** target (and **FrameTV-iOS** if desired).
4. Implement a `RealSMBProvider` conforming to the existing `SMBProviding` protocol (the integration
   notes are written inline at the bottom of `Services/SMBService.swift`).
5. Switch the active provider in `AppEnvironment` from `MockSMBProvider` to `RealSMBProvider`.

Everything above the provider — the browse UI, the file model, the player handoff — already works,
so this is a contained swap.

---

## Architecture

A light MVVM / service-oriented layout:

- **Models** — `MediaItem`, `SMBShare`, `RemoteFileItem`, Real-Debrid response types, `SourceType`.
- **Services** — `LibraryStore` (persistence), `PlaybackProgressStore`, `KeychainStore`,
  `RealDebridClient` (REST actor), `DirectURLService`, `SMBService`, `MetadataParser`.
- **App** — `AppEnvironment` composition root, `SettingsStore`, `Theme` design tokens, `MockData`.
- **Components** — focusable building blocks: `MediaCard`, `MediaRow`, `SourceCard`,
  `FocusableButton`, `LegalConfirmToggle`, and shared loading/empty/error views.
- **Views** — one folder per screen area (Home, Library, Sources, SMB, RealDebrid, DirectURL,
  Magnet, Player, Settings).

State that should survive relaunch is written as JSON in Application Support. Tokens and passwords
are written only to the Keychain and are never logged.

---

## Privacy & legal

FrameTV has no analytics and no backend of its own. The only network requests it makes go directly to
services you configure (your Real-Debrid account, your SMB host, or a direct link you paste). You
are responsible for ensuring you have the legal right to access anything you add. Magnet and
unverified-link flows require an explicit confirmation that you own or are authorized to access the
content. See **Settings ▸ Privacy & Legal Info** in the app, and `AppStoreReviewNotes.md` for the
App Review summary.

---

## Roadmap (later phases)

- **Phase 3** — Activate full Real-Debrid account flows in production use.
- **Phase 4** — Richer metadata and artwork.
- **Phase 5** — Real SMB via AMSMB2 plus a progressive local streaming bridge for network files.
- **Phase 6** — Device test pass on Apple TV hardware and the iOS family (see `TEST_CHECKLIST.md`).


## Cross-device sync & setup notes

FrameTV syncs your **preferences, SMB sources, and installed addons** across your
devices using iCloud key-value storage, and your **API keys / tokens** sync via
iCloud Keychain. To enable this in your own build, make sure the **iCloud** and
**Keychain Sharing** capabilities are turned on for both targets (the included
`FrameTV.entitlements` already declares the iCloud key-value store). Sign in to the
same iCloud account on each device.

**SMB servers** can be entered as a network name (e.g. `sowens.local`), an IP
address, or a full path such as `smb://sowens.local/Home` (which auto-fills the
server, share, and path fields).

The app uses explicit per-target Info.plist files (`Info-iOS.plist`,
`Info-tvOS.plist`). App Transport Security allows arbitrary loads so you can reach
your own non-HTTPS servers; FrameTV sends no data anywhere except the services you
configure.
