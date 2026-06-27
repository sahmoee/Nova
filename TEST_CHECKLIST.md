# FrameTV — Test Checklist

A manual pass to run on the **Apple TV simulator** and on a **physical Apple TV**, plus a quick
iOS/iPadOS smoke test. Check each item; note anything that fails for follow-up.

## Setup

- [ ] Project opens in Xcode with no missing-file (red) references.
- [ ] **FrameTV-tvOS** scheme builds and runs on an Apple TV simulator (for example Apple TV 4K).
- [ ] **FrameTV-iOS** scheme builds and runs on an iPhone simulator.
- [ ] On first launch, the Home screen shows seeded public-domain sample videos.

## Navigation & focus (tvOS)

- [ ] Top tabs (Home, Library, Sources, Settings) are reachable with the remote and highlight on focus.
- [ ] Cards scale/lift when focused; focus never gets trapped or lost.
- [ ] Horizontal rows on Home scroll smoothly with the remote.
- [ ] Back/Menu returns to the previous screen as expected from every pushed view.

## Home

- [ ] Continue Watching shows items with a visible progress bar.
- [ ] Recently Added and Favorites rows populate from the library.
- [ ] The Sources shortcut row routes to each source screen.

## Playback (Phase 2 core)

- [ ] Selecting a sample opens the player and begins playback.
- [ ] Playback controls (play/pause, scrub) work via the remote.
- [ ] Exit during playback, re-open the same item: it **resumes** near where you left off (if more
      than 30 seconds in and under 90% complete).
- [ ] Watch an item past 90%: it is marked watched and drops out of Continue Watching.
- [ ] Progress survives an app relaunch (position is persisted).
- [ ] Force a bad URL (Direct URL flow) and confirm the player shows an error state with **Retry**.

## Direct URL flow (fully functional)

- [ ] Sources ▸ Direct URL accepts a pasted https link to a video file.
- [ ] Invalid input shows a clear inline error (empty, malformed, unsupported scheme).
- [ ] Legal confirmation appears when required and gates the action.
- [ ] **Add & Play** adds the item to the library and starts playback.
- [ ] **Add to Library** adds without playing and clears the form.

## Library

- [ ] Filter segments (All, Favorites, Recently Added, Continue Watching, by source) update the grid.
- [ ] Opening an item shows the detail sheet with Play/Resume, Start Over, Favorite, and Remove.
- [ ] Favorite toggles update immediately and persist.
- [ ] Start Over clears the resume point and restarts from the beginning.
- [ ] Remove deletes the item and dismisses the sheet.

## Sources management

- [ ] SMB: add a share (host, share name, username, password); it appears in the list.
- [ ] SMB: browsing shows folders and playable videos separately (mock provider in this build).
- [ ] SMB: an empty host surfaces a connection error state with Retry.
- [ ] SMB: password is stored in Keychain (never shown again after saving) and removed on delete.
- [ ] Real-Debrid: pasting a token and connecting shows the account summary (or a clear error).
- [ ] Real-Debrid: removing the token returns the screen to the disconnected state.
- [ ] Magnet: the legal confirmation is always required before submitting.
- [ ] Magnet: without a Real-Debrid token, the screen tells the user to connect one first.

## Settings

- [ ] Resume Playback toggle persists and affects whether playback resumes.
- [ ] Default Quality selection persists.
- [ ] Require Legal Confirmation toggle persists and is reflected in the Direct URL flow.
- [ ] Clear Watch History resets resume points after confirmation.
- [ ] Clear Library removes all items after confirmation (sources/credentials remain).
- [ ] Privacy & Legal Info screen displays the full explanation.

## iOS / iPadOS smoke test

- [ ] App launches in dark mode with the same library.
- [ ] Playback works and resume behaves the same as on tvOS.
- [ ] Forms (Direct URL, SMB add) are usable with the on-screen keyboard.

## Physical Apple TV

- [ ] App installs and launches on hardware.
- [ ] Remote focus, scrolling, and playback feel responsive (no stutter on the rows).
- [ ] A real direct URL to a file you control plays end to end.
- [ ] Resume works across a true app quit (not just backgrounding).

## Phase 3 — Metadata, addons & advanced playback

### Credentials & config
- [ ] Settings ▸ Metadata & Accounts saves a TMDB key (shows "Set" badge afterward).
- [ ] A FrameTVConfig.json placed in Documents is picked up as a fallback when no in-app key is set.
- [ ] In-app keys take priority over the config file.

### Discover & detail
- [ ] With a TMDB key, searching a title returns movie and show results.
- [ ] Without a TMDB key, Discover explains that a key is needed (no crash).
- [ ] Opening a show hydrates seasons/episodes; the season chips switch episode lists.
- [ ] Opening a movie shows a Find Streams action.

### Addons
- [ ] Adding an addon by manifest URL installs it and lists its resources.
- [ ] AIOStreams / Comet quick-add forms accept a configured URL and install.
- [ ] Enable/disable toggles persist across relaunch; Remove deletes the addon.
- [ ] Cinemeta is present on first run (seeded), providing metadata.

### Streams & playback
- [ ] The stream picker lists ranked streams with quality/size/seeders/cached badges.
- [ ] Selecting a direct stream plays; selecting a torrent resolves via Real-Debrid (with a token).
- [ ] Without a Real-Debrid token, a torrent stream shows a clear "connect Real-Debrid" message.
- [ ] Auto-select (when enabled) starts the best stream without showing the picker.

### Advanced player
- [ ] Skip Intro appears during the intro window and jumps past it.
- [ ] Skip Outro appears during the credits.
- [ ] Auto-skip intro (when enabled) skips without a button press.
- [ ] When an episode ends, the next episode auto-plays (if enabled) or offers a Next button.
- [ ] Subtitles menu lists available tracks; selecting one shows it; Off removes it.
- [ ] A broken subtitle never breaks video playback (falls back to plain video).

### Trakt
- [ ] Connect shows a device code + URL and completes after authorizing on another device.
- [ ] Once connected, the watchlist appears in Discover.
- [ ] Watched progress scrobbles (start/stop) when scrobbling is enabled.
- [ ] Disconnect clears the session.

### Backward compatibility
- [ ] A library saved before Phase 3 still loads (old items decode without error).
