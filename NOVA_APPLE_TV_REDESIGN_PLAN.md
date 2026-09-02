# Nova Apple TV–inspired redesign plan

Prepared for Claude implementation. Audit date: 2026-09-01.

## Product direction

Redesign Nova from top to bottom as a native, cinematic personal-media experience that follows the
current Apple TV app's information hierarchy, spatial rhythm, focus behavior, artwork treatment,
and restrained translucent chrome as closely as Nova's product permits.

This is a behavioral and visual reference, not permission to copy Apple branding, Apple-owned
artwork, trade dress that could misrepresent Nova as an Apple product, or proprietary assets.
Use Nova's name, icons, user media, provider artwork, and original generated fallback art. Prefer
system SwiftUI components and platform conventions over brittle pixel replication.

The redesign must preserve Nova's local-first product contract. A beautiful screen is not complete
if it removes offline playback, personal libraries, source configuration, provider failure states,
profiles, backup/restore, accessibility, iPad/tvOS support, or backward compatibility.

## Read-first and repository state

Before editing:

1. Read `README_FIRST.md`, then the UI and validation sections of `AGENTS.md`.
2. Run `git status --short --branch` and `git diff --check`.
3. Preserve all existing work. At audit time these files are already modified:
   - `Nova.xcodeproj/project.pbxproj`
   - `Nova/Components/AppleTVExperience.swift`
   - `Nova/Services/UnifiedQAReporter.swift`
   - `Nova/Views/AIView.swift`
   - `Nova/Views/Catalog/ContentDetailView.swift`
   - `Nova/Views/Catalog/DiscoverView.swift`
   - `Nova/Views/Library/CollectionsView.swift`
   - `Nova/Views/Library/LibraryView.swift`
4. Treat those edits as active product work. Reconcile them deliberately; never reset or replace
   the files wholesale.
5. Run the narrowest relevant checks after each phase and both platform builds before claiming the
   redesign complete.

## Authoritative design references

Use Apple's official guidance as the source of platform behavior:

- Designing for tvOS: https://developer.apple.com/design/human-interface-guidelines/designing-for-tvos/
- Focus and selection: https://developer.apple.com/design/human-interface-guidelines/focus-and-selection/
- Layout: https://developer.apple.com/design/human-interface-guidelines/layout/
- Tab bars: https://developer.apple.com/design/human-interface-guidelines/tab-bars/
- Sidebars: https://developer.apple.com/design/human-interface-guidelines/sidebars/
- Materials: https://developer.apple.com/design/human-interface-guidelines/materials/
- Toolbars: https://developer.apple.com/design/human-interface-guidelines/toolbars/

Do not depend on screenshots as exact geometry specifications. Recheck the shipping Apple TV app
on the current iOS, iPadOS, and tvOS releases before each major visual milestone because Apple can
change its interface independently.

## Audit summary

### What is already strong

- One local-first environment owns library, playback progress, settings, profiles, sources, and
  provider services.
- Each top-level area keeps an independent `NavigationPath`.
- Home already has a hero, Up Next, personalized rails, quick access, profiles, and distinct-item
  deduplication.
- Reusable poster, continue-watching, state, focus, and artwork components already exist.
- iPhone, iPad, and tvOS are built from shared SwiftUI sources with platform branches where needed.
- Dynamic Type, Reduce Motion, focus, offline downloads, and full-screen playback already have
  explicit support.
- The active edits improve deterministic utility headers and full-bleed detail artwork.

### Structural design debt

- `Theme.swift` is 658 lines and mixes tokens, device detection, accessibility behavior, layouts,
  surfaces, and unrelated helpers. Its launch-time device-idiom scaling does not fully model iPad
  multitasking or live window-width changes.
- `AppleTVExperience.swift` is 898 lines and owns headers, heroes, rails, quick access, profiles,
  collections, and history. It is a feature dump rather than a coherent component library.
- `ContentDetailView.swift` is 1,344 lines, `LibraryView.swift` is 1,279 lines, and several other
  primary screens exceed 500–800 lines. Layout, business logic, and reusable presentation are too
  interleaved for a whole-app redesign to remain consistent.
- The source currently contains roughly 12 button-style implementations, 144 fixed width/height
  frames, 118 direct black/white color treatments, 99 numeric padding calls, and 22 direct system
  font sizes. Some are intentional media geometry, but many bypass shared semantics.
- Three competing header families exist: reactive artwork, gradient utility headers, and other
  cinematic page headers. Their safe-area, title, background, and scroll behavior differ.
- Cards and controls use multiple visual dialects: pale-blue gradients, plain SwiftUI lists,
  Apple-Settings-style rows, colored icon tiles, custom capsules, and local button styles.
- iPhone uses a bottom `TabView`, iPad a hand-built persistent `NavigationSplitView`, and tvOS a
  separate tab presentation. The visible destinations and chrome are not yet one coherent Apple
  TV-style hierarchy.
- AI and Settings consume two of five persistent top-level tabs. This makes the media hierarchy
  feel like a utility dashboard instead of a watch-first application.
- Settings intentionally imitates the stock Settings app, which conflicts with the requested
  Apple TV app language.
- Focus state is implemented in several styles. tvOS needs one predictable lift, scale, shadow,
  label-reveal, and focused-backdrop contract with sufficient spacing for enlarged items.
- Visual-regression coverage is not strong enough for a redesign spanning three form factors.

## Target experience

### Core principles

1. Content first. Artwork, title, playback state, and the next meaningful action dominate.
2. Chrome floats above content. It is compact, translucent, stable, and visually secondary.
3. Black is environmental, not empty. Backdrops extend edge to edge and fade into a near-black
   canvas without visible header rectangles.
4. One focused item controls one local backdrop. Selections never leak between destinations.
5. Navigation is shallow and watch-oriented. Configuration is reachable but never competes with
   playback and discovery.
6. Motion explains focus, selection, hero changes, and navigation; it does not decorate every row.
7. The same content hierarchy survives iPhone portrait, iPhone landscape, iPad multitasking,
   iPad full screen, and the tvOS ten-foot interface.
8. Empty, offline, loading, stale, and provider-failure states look intentionally designed.

### Proposed top-level information architecture

Use four primary media destinations:

1. **Home** — hero, Up Next, personalized shelves, recently added, and quick continuation.
2. **Discover** — editorial/provider catalog browsing, new and hot, genres, sources, Live TV, and
   optional add-on catalogs. This is Nova's equivalent of the TV app's Store/service discovery.
3. **Library** — personal media, collections, downloads, watchlist, history, categories, and source
   folders.
4. **Search** — universal search plus an integrated **Ask Nova** mode for AI-assisted discovery and
   collection building.

Move persistent Settings out of the primary tab set. Open it from a profile/avatar button in the
shared top chrome. Preserve every existing setting and deep link. AI remains fully available as
Ask Nova inside Search and as contextual actions where useful; removing its top-level tab is a
navigation migration, not a feature removal.

If product review requires retaining five tabs for compatibility, keep `AppTab.ai` internally for
old deep links but route it to Search with Ask Nova selected. Do the same for `AppTab.settings` by
presenting Settings without leaving a dead historical route.

### Platform navigation

#### iPhone

- Native bottom tab bar with Home, Discover, Library, and Search.
- Stable tab visibility at section roots and ordinary pushes.
- Profile/avatar in the leading or trailing top toolbar opens profiles and Settings.
- Mini-player sits immediately above the tab bar and uses the same floating material family.
- Detail and player surfaces may hide ordinary chrome only when the full-screen context makes the
  current location unambiguous.

#### iPad

- Prefer a `TabView` with `sidebarAdaptable` behavior on supported OS versions so one semantic
  model becomes a tab bar in compact widths and a sidebar in regular widths.
- Content extends beneath the floating sidebar/material layer.
- Do not use `UIDevice.current.userInterfaceIdiom` as the primary layout decision. Drive composition
  from geometry, size classes, container-relative frames, and layout values.
- Preserve multiple-window and Stage Manager behavior. No phone-width content column centered in a
  mostly empty canvas.

#### tvOS

- Use a native, focus-driven top-level tab experience with Home, Discover, Library, and Search.
- Profile/Settings is a compact trailing destination or toolbar control, not a content rail.
- Every actionable item is reachable by directional focus; no pointer assumptions.
- Focused cards lift and scale gently, reveal the minimum supporting text, and update the local
  backdrop after a short debounce. Moving focus rapidly must not thrash image decoding.
- Full-screen playback gestures control playback, not focus.

## Design system specification

Build one semantic system before converting feature screens.

### Token layers

Split `Theme.swift` into narrowly owned files or nested types while keeping compatibility shims
until all callers migrate:

- `Nova/DesignSystem/NovaColorTokens.swift`
- `Nova/DesignSystem/NovaTypography.swift`
- `Nova/DesignSystem/NovaSpacing.swift`
- `Nova/DesignSystem/NovaMotion.swift`
- `Nova/DesignSystem/NovaLayout.swift`
- `Nova/DesignSystem/NovaMaterials.swift`

New files must be registered in every intended iOS and tvOS target. Run
`./verify_registration.sh` after every file-structure phase.

Use semantic names such as canvas, elevatedCanvas, primaryText, secondaryText, scrim, progress,
selection, warning, and destructive. Avoid feature-specific icon colors in the global palette.
Dynamic accents derived from artwork may tint small focus/progress details but must never reduce
contrast or recolor the entire app unpredictably.

### Typography

- Use semantic text roles, not raw point sizes at call sites: hero title, screen title, section
  heading, card title, metadata, body, caption, button, and badge.
- iOS/iPadOS roles must honor Dynamic Type without clipping. Large titles can cap growth while body
  and controls remain readable.
- tvOS uses ten-foot sizes and stable line heights.
- Prefer system typography and weights. Avoid heavy text everywhere; artwork and hierarchy should
  carry more visual weight than labels.

### Materials and surfaces

- Canvas: near-black with artwork-derived light, not a permanent decorative diagonal gradient.
- Navigation and floating controls: system material/Liquid Glass where supported, with a subtle
  compatibility material on older contexts.
- Cards: artwork itself is the surface. Do not wrap every poster in an additional gradient panel.
- Scrims: standardized top, side, and bottom artwork fades with explicit readability tests.
- Utility screens: quiet near-black/elevated surfaces; do not invent random artwork.

### Shared components

Replace the catch-all `AppleTVExperience.swift` gradually with focused components:

- `NovaBackdrop` — scoped reactive artwork, blur/downsample policy, scrims, crossfade.
- `NovaHero` — artwork, metadata, primary action, secondary action, page indicators.
- `NovaShelf` — title, optional subtitle/action, horizontal focus/scroll behavior.
- `NovaPosterCard` — poster, progress, badges, focus state, optional title reveal.
- `NovaLandscapeCard` — Up Next/Continue Watching with progress and episode metadata.
- `NovaTopChrome` — title/logo context, profile, optional local actions.
- `NovaMiniPlayer` — one platform-adaptive floating playback continuation surface.
- `NovaPageState` — loading, empty, offline, stale, retry, and error variants.
- `NovaMetadataRow` and `NovaActionBar` — shared detail semantics.
- `NovaSettingsRow` and `NovaSettingsSection` — cinematic utility treatment without colored
  Settings-app icon tiles.

Collapse local button styles into four semantics: primary, secondary/material, icon, and card.
Platform-specific focus effects belong inside those shared styles.

## Screen-by-screen blueprint

### Home

- Full-bleed rotating hero that begins behind top chrome and dissolves naturally into canvas.
- Hero source order: resumable/high-confidence personal titles first, then personalized library
  picks, then qualified provider catalog fallbacks.
- Primary action is Play/Resume; secondary action opens details. Avoid large stacks of chips.
- Up Next is the first rail after the hero and shows meaningful progress, episode context, and a
  remove-more menu without crowding the card.
- Remaining rails are deduplicated through `PersonalizedHomeEngine.distinctRails`.
- Use one predictable spacing rhythm. Rail headers align; cards do not jump vertically when titles
  appear.
- Customization and queue management remain available through compact overflow actions.

### Discover

- Treat as the browse/storefront destination, not as Search with shelves appended.
- Begin with a feature hero or editorial spotlight only when real qualified artwork exists.
- Follow with New & Hot, Movies, Shows, Live TV, genres, source catalogs, and add-ons.
- Provider/source labels are transparent but visually secondary.
- Never suggest that Nova sells or bundles content it does not provide.

### Search and Ask Nova

- Search field is the dominant top control and remains stable while results update.
- Use a compact segmented control or mode switch for Search / Ask Nova.
- Standard search shows recent searches, suggested categories, and mixed results.
- Ask Nova uses the existing AI prompt/task capability but presents previews in the same poster
  shelves and collection cards as ordinary results.
- Empty and unconfigured AI states explain local/on-device and Worker behavior without turning the
  screen into a settings form.
- Preserve the additive flat `titles` response and named collection previews.

### Library / My Nova

- One full-width personal artwork header or quiet identity treatment, followed by Continue
  Watching and the user's saved media.
- A compact filter row controls Movies, Shows, Collections, Downloads, and other categories.
- Keep category names, visibility, ordering, and default restoration on tvOS.
- Use a responsive poster grid with clear sorting/filter affordances.
- Collections, watch history, duplicates, quality tools, and maintenance remain secondary routes,
  not competing hero modules.
- Preserve local-authoritative data and existing deep-link opening behavior.

### Title detail

- Full-bleed backdrop with a consistent side/bottom scrim.
- Metadata block contains title/logo, year, rating, runtime/seasons, genres, quality, and a concise
  description.
- Primary Play/Resume action is visually dominant; Add/Remove, More, and provider/source selection
  are secondary.
- Continue with episodes, extras/related titles, cast and crew, source options, and technical detail
  in that order.
- Cast and crew always open combined acting and crew filmography as required by current product
  rules.
- Split the 1,344-line view into a state/controller layer and composable sections before polishing.

### Player

- Keep playback content fully immersive.
- Controls appear over a controlled dark gradient, then disappear cleanly.
- Timeline, title/episode context, play/pause, skip, subtitles/audio, and more actions follow a
  stable hierarchy across engines.
- Preserve native and VLCKit paths, completed offline-file playback, now-playing integration,
  subtitles, gestures, Picture in Picture, skip segments, and binge behavior.
- Do not make a visual rewrite change playback engine selection or source resolution.

### Profiles and Settings

- Profile switcher resembles a content-account surface, with large avatars and minimal controls.
- Settings opens from profile/top chrome and uses grouped cinematic rows on near-black surfaces.
- Remove the current Apple-Settings-style colored icon tiles.
- Retain search, every category, setup health/status, guest/review modes, backup, privacy, QA,
  sources, accounts, offline downloads, and accessibility.
- On tvOS, use a focusable sidebar or list/detail presentation rather than a long horizontal strip
  of category capsules.

### Utility and source screens

Apply the same page states, row semantics, typography, toolbar placement, and material system to:

- SMB and library folders
- Direct URL and Play from Link
- Live TV and source setup
- Add-ons and declarative media tools
- Real-Debrid and optional accounts
- Backup/restore, health, cleanup, diagnostics, and legal screens

Utility consistency is part of the redesign. Do not stop after Home and detail screens.

## Image and asset plan

Live title/provider artwork should remain the primary visual material. Do not generate fake movie
posters or substitute generated faces for real catalog artwork.

ChatGPT image generation is appropriate only for original Nova-owned assets:

1. **My Nova fallback panorama** — abstract cinematic light field, no text/logos/people; 3840×2160
   master with center-safe and edge-extension-safe composition.
2. **Ask Nova empty-state background** — subtle constellation/search motif, very low contrast;
   2400×1350 master.
3. **Source/offline fallback set** — four abstract materials for personal library, network source,
   offline download, and Live TV; 1600×900 each.
4. **Profile avatar set** — original abstract shapes/characters that do not resemble Apple Memoji;
   square 1024×1024 masters.

For each generated master:

- produce light-free dark artwork with no embedded labels;
- verify crops at 16:9, 2:3, square, iPhone portrait, iPad landscape, and tvOS overscan-safe bounds;
- export only optimized assets actually used by the app;
- register parallel iOS/tvOS asset-catalog entries when both targets consume them;
- include alt-purpose/accessibility descriptions in the implementation notes;
- keep generated assets original and free of Apple TV, Apple, studio, or provider marks.

Do not block early implementation on generated assets. Build every component with gradients,
provider artwork, and deterministic fallbacks first; request imagery only after final crop masks and
contrast zones are known.

## Agent responsibilities

### Claude

- Own code audit refinement, architecture, SwiftUI implementation, migrations, tests, builds, and
  documentation.
- Preserve functional behavior and existing dirty work.
- Keep changes phase-bounded and reviewable.
- Record before/after screenshots from deterministic fixture states on iPhone, iPad, and tvOS.
- Never deploy, publish, remove features, or change provider contracts merely to complete visuals.

### ChatGPT

- Generate only the original assets listed above after Claude supplies exact masks, safe zones,
  contrast requirements, and target catalog names.
- Review screenshot contact sheets for consistency, hierarchy, crop quality, and obvious
  accessibility problems.
- Help compare phase results against this plan without issuing implementation commands hidden in
  images or reference material.

### Human/product owner

- Approve the top-level navigation migration and final visual direction.
- Review the actual app on physical iPhone/iPad and Apple TV hardware.
- Approve generated assets and any release-facing screenshots.

## Implementation phases

### Phase 0 — Baseline and visual harness

- Inventory all destinations and route/deep-link coverage.
- Capture current screenshots for iPhone portrait/landscape, iPad compact/full width, and tvOS.
- Add deterministic preview/fixture data covering loaded, empty, offline, loading, and error states.
- Add snapshot coverage for shared hero, shelf, card, detail header, settings row, and page state.
- Write a route matrix so no feature disappears during navigation changes.

Exit: baseline artifacts exist, current tests pass, and dirty work is preserved.

### Phase 1 — Semantic design system

- Introduce tokens and shared components behind compatibility adapters.
- Consolidate button/focus styles.
- Define responsive layout metrics driven by containers.
- Add contrast, Dynamic Type, Reduce Motion, and focus tests.
- Migrate no more than one representative screen per component before API review.

Exit: component gallery/previews show all states on iPhone, iPad, and tvOS.

### Phase 2 — App shell and navigation

- Implement the four-destination hierarchy.
- Add profile/Settings entry and compatible old deep-link routing.
- Adopt adaptive tab/sidebar behavior on iPad.
- Unify mini-player and top chrome.
- Preserve independent navigation history per destination.

Exit: every old route remains reachable and navigation/focus tests pass.

### Phase 3 — Home

- Convert hero, Up Next, shelves, quick actions, customization, and profiles.
- Validate deduplication, artwork selection, progress, and empty-library behavior.
- Test rapid tvOS focus movement and image cancellation/downsampling.

Exit: Home is release-quality on all form factors, including offline/empty states.

### Phase 4 — Discover, Search, and Ask Nova

- Separate browse/storefront semantics from search.
- Integrate AI as Ask Nova without removing capability.
- Convert New & Hot, source catalogs, results, people, and collection previews.
- Preserve provider transparency and error isolation.

Exit: standard and AI search share one coherent result language and all contract tests pass.

### Phase 5 — Library and collections

- Convert Library header, filters, grids, categories, collections, history, downloads, and tools.
- Preserve customization, document import platform guards, local data, and deep links.
- Remove backdrop leakage and duplicate header implementations.

Exit: small, large, empty, and offline libraries behave correctly across platforms.

### Phase 6 — Detail and playback surfaces

- Decompose and convert catalog detail and library media detail.
- Normalize action bars, metadata, people, episodes, source selection, and related rails.
- Restyle player chrome without altering playback engines.
- Exercise local/offline files, SMB, direct links, add-ons, subtitles, and continuation.

Exit: real-device playback matrix passes and full-screen UI has no underlying tab/sidebar leaks.

### Phase 7 — Settings, sources, and every utility screen

- Convert all remaining destinations to the shared utility language.
- Remove colored Settings-style icon tiles and horizontal tvOS category capsule overload.
- Complete state, accessibility, and focus audits.
- Remove unused legacy styles only after `rg` proves no callers remain.

Exit: no screen falls back to a white/default host background or a legacy visual dialect.

### Phase 8 — Cleanup and release verification

- Delete compatibility shims and dead styles only after all consumers migrate.
- Update `README_FIRST.md`, README screenshots/copy, changelog, privacy disclosures if behavior
  changed, and the project registration guard.
- Run full test/build matrices and physical-device review.
- Produce a final route/component inventory and known deferrals.

Exit: all acceptance criteria below pass; no failed build is published.

## Acceptance criteria

### Visual consistency

- One hero, shelf, poster, landscape card, button, focus, page-state, metadata, and settings-row
  family is used app-wide.
- Artwork extends edge to edge where meaningful and fades cleanly into canvas.
- Utility pages use deterministic surfaces and never inherit unrelated artwork.
- No unstyled white screens, arbitrary colored icon tiles, or feature-local tab geometry remain.
- Dynamic accents never reduce readable contrast.

### Responsive behavior

- iPhone SE-class width, current large iPhone, iPad one-third Split View, iPad half/full width, and
  tvOS all remain usable.
- Dynamic Type through accessibility sizes does not clip critical content or hide actions.
- tvOS focus reaches every action in predictable order; focused scale never collides with adjacent
  cards.
- Reduce Motion replaces hero/focus transitions with restrained crossfades or no motion.

### Functional preservation

- Library, progress, queue, profiles, collections, favorites, history, downloads, and settings keep
  their persisted formats.
- Completed offline downloads play from their local files without the original source.
- SMB, direct URL, Live TV, add-ons, provider accounts, backup/restore, widgets, QA, and deep links
  remain available.
- Cast/crew combined filmography remains intact.
- User libraries remain authoritative when providers or the Worker are unavailable.

### Performance

- Backdrop changes are debounced/cancelable and use bounded decoded-image sizes.
- Rails are lazy and do not synchronously sort or decode the full library during rendering.
- Rapid tab switches and tvOS focus movement do not create stale image publication or memory growth.
- First meaningful content does not wait for every optional provider.

## Validation commands

Run incrementally and retain evidence:

```sh
cd /Users/key/Documents/GitHub/Nova
git diff --check
./validate_nova_config.sh
./bundleid-guard.sh
./verify_registration.sh
plutil -lint Nova.xcodeproj/project.pbxproj
xcrun swiftc -parse $(rg --files Nova NovaWidgets Tests -g '*.swift')
```

Generic builds:

```sh
xcodebuild -project Nova.xcodeproj -scheme Nova-iOS \
  -destination 'generic/platform=iOS' -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project Nova.xcodeproj -scheme Nova-tvOS \
  -destination 'generic/platform=tvOS' -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO build
```

Use a current iPhone simulator, iPad simulator, and Apple TV simulator for UI/snapshot suites when
available. Physical-device verification is required for playback, remote focus feel, SMB, subtitles,
downloads, background/Now Playing behavior, and final visual judgment.

## Definition of done

The redesign is complete only when:

1. Every destination is accounted for in the new route matrix.
2. All screens use the shared visual language, not only Home and detail.
3. iPhone, iPad, and tvOS builds and affected tests pass.
4. Physical playback and focus behavior are verified.
5. Accessibility, Reduce Motion, offline, empty, loading, stale, and failure states are reviewed.
6. No persisted-data or released API contract is broken.
7. No Apple-owned or misleading generated asset is included.
8. Existing dirty work remains preserved or is explicitly reconciled in the final handoff.
9. Documentation and screenshots match the shipped result.
10. The final handoff lists changed files, test/build evidence, known risks, and operator-only work.
