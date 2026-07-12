# Astra 1.8 — Apple TV Experience Rehaul

Astra now uses one Apple TV-style information architecture across iPhone, iPad, and Apple TV while keeping each target's unsupported APIs out of its build and UI.

## 10 large features

1. **Adaptive native app shell** — native bottom tabs on iPhone, a persistent sidebar on iPad, and focus-driven television tabs on tvOS. Each section keeps an independent navigation stack.
2. **Synced viewing profiles** — up to six profiles, profile icons, a kids-profile preset, active-profile switching, and iCloud-synced experience preferences.
3. **Unified Up Next** — Continue Watching and the ordered queue are deduplicated into one Apple TV-style rail with resume, restart, remove, and queue management.
4. **On-device Top Picks** — personal ranking uses favorites, queue position, recency, progress, series activity, preferred tags, and artwork quality without uploading watch history.
5. **More Like This recommendations** — the most recently watched title can create a TMDB recommendation rail when the user has supplied a TMDB key.
6. **Automatic Smart Collections** — Finish Tonight, Binge Next, Unwatched Favorites, 4K & High Quality, Personal & Network Media, Watch History, Rediscover, and Recently Added update themselves.
7. **Watch History timeline** — a dedicated chronological history with progress, mark-unwatched, remove-from-history, and detail navigation.
8. **Quick Access hub** — one-tap tiles for Library, Live TV, Collections, Watch History, Smart Collections, and Sources.
9. **Source Health hub** — Home shows connection state for Real-Debrid, TMDB, Trakt, addons, and SMB, with a direct route to source management.
10. **Editorial Watch Now feed** — personal rails and user-configurable TMDB/Trakt/addon shelves now coexist in one continuous cinematic feed with a full-bleed hero.

## 5 medium features

1. **Search-first navigation** — Discover is presented as Search in the app shell, with a Home search shortcut.
2. **Cross-platform mini-player** — a persistent Now Playing surface with progress, resume, and close controls; it adapts to tab bars, the iPad sidebar, and tvOS focus spacing.
3. **Experience controls in Settings** — profiles, hero rotation, Quick Access, Source Health, Smart Collections, Watch History, recommendations, and reduced artwork motion.
4. **Adaptive rail density** — poster and landscape card sizing is tuned separately for iPhone, iPad, and Apple TV.
5. **Unified quick actions** — poster context menus retain queue, favorite, watched, hidden, and library actions throughout the new rails.

## 3 low-effort improvements

1. Apple TV-style animated capsule page indicators for featured titles.
2. More consistent thin-material cards, hairline borders, focus elevation, and near-black cinematic surfaces.
3. Improved empty/setup states that route directly to Sources, TMDB setup, queue, or profile selection.

## Platform capability boundary

`PlatformCapabilities.swift` is the single capability map. Platform-only controls are omitted rather than shown in a broken or disabled state.

| Capability | iPhone | iPad | Apple TV |
|---|---:|---:|---:|
| Bottom tab navigation | Yes | No | No |
| Persistent sidebar | No | Yes | No |
| Television focus tabs | No | No | Yes |
| Haptics | Yes | Yes | No |
| Widgets | Yes | Yes | No |
| Spotlight indexing | Yes | Yes | No |
| QR scanner | Yes | Yes | No |
| Share sheet | Yes | Yes | No |
| External players | Yes | Yes | No |
| Picture in Picture | Yes | Yes | No |
| Top Shelf | No | No | Yes |
| Focus engine / remote menu | No | No | Yes |
| SMB, catalog, library, playback, profiles | Yes | Yes | Yes |

## Main implementation files

- `Astra/App/PlatformCapabilities.swift`
- `Astra/Services/ViewingProfileStore.swift`
- `Astra/Services/PersonalizedHomeEngine.swift`
- `Astra/Components/AppleTVExperience.swift`
- `Astra/Views/RootView.swift`
- `Astra/Views/Home/HomeView.swift`
- `Astra/Views/Settings/SettingsView.swift`
- `Astra/App/Theme.swift`

The four new Swift files are registered in both the iOS/iPadOS and tvOS app targets. iOS-only widgets and tvOS-only Top Shelf remain separate extension targets.
