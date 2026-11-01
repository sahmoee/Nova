# Nova: Omni-style UI/UX redesign

Status: phases 0–7 implemented 2026-11-01 (restore tag `restore/nova-pre-omni-2026-11-01`). Supersedes the
2026-09-24 gray/black pastel direction and the 2026-09-09 tvOS floating Back menu. See "Implementation
notes" at the end for what shipped and what remains.

## Goal

Rebuild Nova's presentation layer on the interaction model of Omni 1.7 for tvOS. Omni is a SwiftUI
Stremio-addon client, analyzed in `omni-teardown.md`. Nova keeps "subtle differences" so it reads as its own
product. The data layer, services, stores, playback engines, deep links, widgets, watch app and
policy checks stay as they are. Only views, navigation chrome and visual tokens are replaced.

Omni ships only on tvOS. iOS, iPadOS and Mac Catalyst get the same information architecture, adapted
to their own input models.

## What we know about Omni's UI

Recovered from Swift type names, view state names and settings keys in the unencrypted binary. No
screenshots were available, so proportions and spacing below are Nova's own choices.

| Omni element | Evidence | Behavior |
|---|---|---|
| `CustomSidebar` | `_sidebarStyle`, `_focusedSidebarIndex`, `_focusSidebarStyleOption`, `SidebarItemsPreference` | Persistent left sidebar on tvOS, user-reorderable items, selectable style |
| `FeaturedHeroView` | `_logoURL`, `_bottomAlignLogo`, `_preloadedLogos`, `HeroCache`, `_isShowingContentBelowHero` | Full-bleed backdrop, clear-logo title (bottom-aligned option), hero collapses once focus moves into rows |
| `TopRowCatalogShelf` | `_topRowCatalogs`, `_smallTopRowCatalogs`, `_topRowItemLimits` | First shelf directly under the hero, can be small, has a per-catalog item limit |
| `StremioCatalogShelf` | `_landscapeCatalogs`, `_posterSize`, `_posterType`, `_alwaysShowTitles` | Each catalog row can be poster or landscape. Size and type are global settings. Titles show on focus or always |
| `ContinueWatchingShelf` | `_smallContinueWatchingShelf` | Landscape progress cards, optionally compact |
| Catalog groups | `CatalogGroupItem`, `GroupCatalogView`, `MainGroupListItem` | Several catalogs collapse into one grouped destination |
| `TitleView` | `_glowTitleViewEnabled`, `_focusedActionButton`, `EpisodeEntry`, `SeasonEntry` | Backdrop page with logo, actions row, seasons and episodes, trailers, recommendations |
| `StreamsView` | `_focusedStreamId`, `OrderedRegexPattern`, `_isProviderMenuFocused` | Full-page stream list with user-rule colored tags and a provider filter menu |
| `TrailerShelf`, `AIShelf`, `StremioLiveTVShelf` | type names | Optional Home shelves |
| Focus | `_highContrastFocus` | Accessibility option for a stronger focus ring |
| Settings | `settings.category.*` | Flat categories: Addons, Catalogs, Groups, Player, Auto-Play, Regex, Search, Trakt, UI, iCloud, Cache, Web Management, Legal |

## Subtle differences (Nova identity)

1. **Sidebar:** Omni-style persistent sidebar. Nova's version collapses to a narrow 96 pt icon rail
   until focused, expands to 320 pt with labels, and uses Nova's serif wordmark in place of an app name.
2. **Hero:** logo-first like Omni. Nova adds a soft bottom scrim tuned per artwork luminance and keeps
   its real metadata line (year · runtime · rating · genres). It doesn't auto-advance while the user is
   reading, and it pauses entirely under Reduce Motion.
3. **Accent:** Omni's chrome is neutral. Nova keeps one restrained accent (its existing `AccentManager`
   value) for progress bars and selection, never as a glow behind artwork.
4. **Cards:** 12 pt continuous corners (Omni's look is unknown), titles under posters by default, and
   tvOS system focus lift. Nova's high-contrast focus adds a 4 pt white stroke.
5. **Streams:** Omni's full-page list. Nova keeps its badge parser (`SourceBadges`) and adds user stream
   rules (see phase 4) in place of raw regex.
6. **Settings:** Omni's flat category list, folded into Nova's six categories so existing policy docs
   stay valid.

## Information architecture

| Destination | tvOS | iPad / Mac | iPhone |
|---|---|---|---|
| Home | sidebar | sidebar | tab bar |
| Search (+ Smart Search) | sidebar | sidebar | tab bar |
| Movies (catalog group) | sidebar | sidebar | Home segment |
| Series (catalog group) | sidebar | sidebar | Home segment |
| Live TV (when sources exist) | sidebar | sidebar | Home segment |
| Library | sidebar | sidebar | tab bar |
| Settings | sidebar footer | sidebar footer | tab bar |

Movies and Series are new roots built from `CatalogService` catalogs filtered by type, Omni's
`GroupCatalogView` pattern. `AppTab` gains `.movies`, `.series` and `.liveTV`. `.ai` still routes into
Search, as Nova's compatibility rules require.

## What gets removed

- `TVMenuOverlay` floating Back menu and `openTVMenu` / `setTVRootVisible` environment plumbing
- `NovaHomeBar` floating iPhone bar (replaced by the system `TabView`)
- `TVHomeExperience` / `AppleTVExperience` hero and rail layouts, `FeaturedHero`
- `TVReferenceStyle` geometry and the pearl/graphite pastel tokens in `Theme`
- Content-detail layout in `ContentDetailView` / `MediaDetailView` (logic moves into a view model)

Kept as they are, then restyled through the new tokens: player views (VLC/AVPlayer), Settings sub-pages
(servers, SMB, Real-Debrid, accounts, backup), Library grid logic, Live TV EPG, and all stores and
services.

## Phases

| # | Scope | Done when |
|---|---|---|
| 0 | Restore tag `restore/nova-pre-omni-2026-11-01`; new `OmniTheme` tokens (canvas, surfaces, focus, typography) | Builds unchanged |
| 1 | **Shell:** `NovaSidebar` (tvOS rail and expanded states, iPad/Mac split view), system `TabView` on iPhone, `AppTab` additions, delete the TV menu overlay | All three schemes build. Remote can reach every root. Back from a root opens the sidebar |
| 2 | **Home:** logo hero with content-below-hero collapse, top row shelf, poster/landscape catalog rows, compact Continue Watching, shelf order and size settings | Home renders from live catalogs. Settings toggles change layout |
| 3 | **Title page:** backdrop + logo, actions row, seasons/episodes, trailers, cast, recommendations | Parity with current detail features |
| 4 | **Streams page:** full-page list, provider filter, user stream rules (match text → tag color, boost, hide, auto-play) | Rules persist, rank and auto-select in tests |
| 5 | **Catalog management:** rename, reorder, pin to top row, landscape toggle, groups | Edits persist via `SettingsStore` and iCloud mirror |
| 6 | Settings restyle into the flat Omni-like list, high-contrast focus, poster size/type options | Policy checks pass |
| 7 | Docs: README_FIRST, UI audit, ProjectKnowledge entries updated to describe the new UI | Old pastel/Back-menu rules retired |

## Functional ideas from Omni worth porting (beyond UI)

| Feature | Value | Notes |
|---|---|---|
| User stream rules (Omni "Regex") | High | Phase 4. Use bounded literal/regex matching with a compile check and length cap |
| Top Shelf extension | High | Nova only has a capability flag. Feed it Continue Watching from the App Group |
| MDBList aggregated ratings | Medium | User-supplied key in Keychain. Complements `OMDbClient` |
| External player handoff (Infuse etc.) | Medium | `PlayerOptions` already references Infuse. Add x-callback return handling |
| Trakt as a virtual catalog source | Medium | Omni's `TraktBridgeService` |
| HLS remux for Atmos on AVPlayer | Low/High effort | Needs FFmpeg. Skip unless VLC Atmos is insufficient |
| HomeKit/Govee ambient lighting | Low | New entitlement and privacy string. Optional later |
| Embedded management web server | Not recommended | Conflicts with Nova's "no web server on Apple TV" policy. Omni's has no auth |
| Jailbreak detection | Not recommended | Little user value |

Do not copy Omni's name, icon, Top Shelf art, HTML pages or support/Discord branding. Nova uses only its
own assets and live artwork.

## Open input needed

Screenshots or a short screen recording of Omni on Apple TV (Home, a title page, Streams, the sidebar
expanded) would turn the inferred layout above into a measured one. The IPA is a device build and can't
run in the tvOS Simulator.

## Implementation notes (2026-11-01)

| Phase | What shipped | Key files |
|---|---|---|
| 0 | Restore tag; black canvas, neutral surfaces, 12–14 pt corners; Nova violet accent (`AccentManager.fallback`); `OmniStyle` geometry and `OmniLayoutKey` settings | `App/Theme.swift`, `App/OmniStyle.swift`, `Services/AccentManager.swift` |
| 1 | tvOS `NovaSidebar` (icon rail or hidden, expands on focus; Back from a root focuses it); iPad/Mac split view with the same sections; iPhone system `TabView`; `.movies`/`.series` roots and `nova://movies`, `nova://shows`, `nova://series`; floating menu, `NovaHomeBar` and `MenuOverlay` removed | `Views/RootView.swift`, `Views/TVMenuOverlay.swift`, `App/NavigationCoordinator.swift`, `App/DeepLink.swift`, `Views/Catalog/CatalogBrowseView.swift` |
| 2 | Home: logo-first hero fed by the first Top Row catalog (history fallback), collapses and previews the focused title on tvOS; Continue Watching; Top Row then remaining catalogs; iPhone browse chips | `Views/Home/HomeView.swift`, `Components/OmniHome.swift`, `Components/OmniRows.swift` |
| 3 | Title page header: full-bleed backdrop, TMDB logo, year/type/genres/rating, one action row (Play, Trailer, Watched, Favorite, More) | `Views/Catalog/ContentDetailView.swift` |
| 4 | Stream Rules: text or regex, tag color, prefer/avoid/hide, auto-play picks; ranking and auto-select integration; tags on stream rows; iOS import (previewed) and export | `Services/StreamRules.swift`, `Services/StreamRanker.swift`, `Views/Settings/StreamRulesView.swift`, `Tests/StreamRuleTests.swift` |
| 5 | Catalog Management: rename, show/hide, Top Row pin, poster/landscape, item cap, up/down reorder, remove; `ShelfConfig` decodes older saved data | `Views/Home/HomeCustomizeView.swift`, `Models/HomeShelf.swift` |
| 6 | Appearance settings: card size, always-show titles (tvOS), compact Continue Watching, hero rotation and logos, sidebar style (tvOS), high-contrast focus | `Views/Settings/AppearanceSettingsView.swift` |
| 7 | What's New 1.7 rewritten; this document | `Services/WhatsNew.swift` |

Remaining follow-ups:

- Screens not rebuilt: Search/Discover, Library, Live TV and the player keep their layouts and only pick up
  the new tokens. `CatalogShelfRow`, `TVHomeExperience` and `FeaturedHero` are still used by those screens.
- Stream rules and layout settings are stored locally per device; they are not yet in the iCloud mirror
  or setup backups.
- Interactive remote/focus behavior was checked by build and screenshot only; walk the sidebar, hero
  collapse and Back behavior on a real Apple TV.
- Omni screenshots would let the proportions here be matched more closely.

## iPhone and iPad specifics from Omni iOS (2026-11-01)

| Omni iOS element | Nova iOS | Files |
|---|---|---|
| `stremio://` addon links | Registered on iOS and Mac. Links map to the HTTPS manifest and always ask before installing (credentials and non-manifest links are rejected) | `App/DeepLink.swift`, `Views/RootView.swift`, `Tests/AddonLinkTests.swift` |
| Blurred hero art behind Home | A dimmer blur of the shown hero art fades behind the rows on iPhone, iPad and Mac | `Views/Home/HomeView.swift` |
| Catalog group cards | Glass Movies / Series / Live TV / Collections cards with a two-poster peek, on iPhone | `Components/OmniHome.swift` |
| Glass buttons | Secondary hero and title buttons use Liquid Glass; the primary button stays solid white | `Components/OmniHome.swift` |
| Expandable description | Three-line synopsis with a More/Less toggle on the iPhone title page | `Components/OmniHome.swift`, `Views/Catalog/ContentDetailView.swift` |
| Stream button ordering | Stream Rules › Row Details picks and orders the details on each stream row (all platforms) | `Views/Settings/StreamRulesView.swift`, `Views/Catalog/StreamPickerView.swift` |

Follow-ups worth porting: a TMDB keyword Discover editor, Trakt list browsing and creation, an
accent color picker, reviews and cast profile sheets, a custom player overlay, and iPhone-as-remote
pairing with Apple TV.
