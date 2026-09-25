> **Shared rules live in the master doc:** read `/Users/key/Documents/CLAUDE_ALL_PROJECTS_HANDOFF.md` first for the
> shared safety, QA, build-numbering, endpoint, machine, and cross-project delivery contracts.
> This file holds only Nova-specific facts.

# Read me first

September 24: the user requested Stocked’s softer styling in gray/black for Nova. Shared surfaces,
headers, controls, navigation, settings and accent assets now use charcoal/graphite/pearl. Restore
tag: `restore/nova-pre-pastel-2026-09-24`. See `docs/PASTEL_GRAY_REDESIGN_2026_09_24.md`.

Nova is a local-first iOS/iPadOS/tvOS personal-media app. User libraries and progress are authoritative; remote metadata, AI, tracking, and sharing are optional. Start in `Nova/App`, then the relevant `Nova/Services` or `Nova/Views` area. Keep credentials in Keychain, never source control.

Nova's media-server index accepts user-configured Jellyfin, Plex, and Emby servers. `MediaServerStore`
owns connections and refresh orchestration, `MediaServerClient` performs read-only provider paging and
normalization, and `LibraryStore` atomically reconciles each server while retaining watch state and
alternate playable copies. Tokens remain in Keychain. The local Library is the consumer for Home,
Search, Spotlight, widgets, and playback; remote servers remain authoritative for availability.
Server removal is recoverable by reconnecting and reindexing, and removing indexed titles is a
separate explicit choice. See `docs/MEDIA_SERVER_INDEX.md`.

The September 5 fifty-improvement pass is recorded in docs/NOVA_50_IMPROVEMENTS_2026_09_05.md.
Requests honor provider cooldown minima and monotonic retry budgets. Download actions/callbacks
respect transfer identity and lifecycle; only owned files are played/deleted, and failed migration
retains legacy data. Live channels never acquire VOD resume points; malformed numeric state repairs
on read. Source-picker work is cancellable/generation-guarded; all automatic picks and failover honor
visible filters and the required-cached preference. Returning from playback does not auto-replay.
Prompts protect drafts; subtitle selection and offline queue states remain shared across platforms.

Nova uses Apple platform styling throughout: a soft charcoal canvas, graphite surfaces, serif display headings, San Francisco body typography, semantic state colors, and compact system controls. iPhone and iPad use pearl gray for actions and selection. tvOS uses the native neutral white focus surface with dark text and a restrained lift. Media artwork supplies the color; app chrome follows the September 24 gray/black pastel palette without artwork-derived tint or colored glow. Keep top-level controls condensed.

Primary navigation is Home, Search, Library, and Settings. Smart Search is integrated inside Search; `AppTab.ai` and `nova://ai` exist only for compatibility and must route into Search. iPhone uses the shared floating `NovaHomeBar`, iPad uses its sidebar, and tvOS uses the Back menu. tvOS Settings uses a six-category native directory; selecting a category pushes one independently scrolling destination. See `docs/UI_UX_REDESIGN_2026_09_09.md`.

Search → Browse and Live TV expose a Sports directory for official providers. On iPhone and iPad,
provider pages stay inside a popup-blocking `WKWebView`; new-window requests never create another
web view, and JavaScript alert/confirm popups are suppressed. Apple TV presents a QR handoff because
tvOS has no general web browser. Users may also paste their own HTTPS address after an explicit
unverified-site warning; Nova rejects non-HTTPS links and embedded URL credentials, applies the same
popup protections on iPhone/iPad, and uses QR handoff on Apple TV. Nova does not endorse, index,
extract, resolve, or bypass access controls for pasted websites. Provider authentication,
subscription availability, permissions, and playback remain provider- or user-owned.
Nova intentionally does not expose Formula 1 or music-provider integrations in this directory.

tvOS navigation is a floating Back menu with Remote, Home, Search, Library, and Settings. A root page's heading or the remote Back button opens it; Back closes the open menu. Pushed destinations retain native Back navigation. RootView keeps visited sections mounted while excluding inactive sections from interaction and accessibility. The root-only Now Playing bar follows the same menu behavior. TVPageHeading and TVReferenceStyle own the shared television heading and geometry. Preserve the iPhone bottom tab bar and iPad sidebar independently of tvOS changes.

Home is an artwork-first streaming storefront. On tvOS, the hero leads with title artwork (or a text fallback), real metadata, a short synopsis, Play/Resume, Up Next, information, circular page indicators, and landscape Continue Watching cards. Source setup, source health, profile editing, and shelf customization belong in Settings instead of Home. The iPhone/iPad feed retains its own hero, rails, and Discover composition. Use Nova's live artwork and destinations; do not embed reference-screen branding, sample titles, or imagery.

The Home hero extends beneath the top safe area. Its visible artwork is aspect-fit so the complete composition remains visible without stretching; a restrained full-bleed copy may sit behind it to fill the canvas when source aspect ratios differ.

Reactive artwork remains scoped to the destination that owns it: selections must not leak between Library, Search/Discover, Collections, and AI. Preserve the iPhone/iPad artwork behavior. tvOS Library is an explicit exception to the artwork-header layout: its compact heading and All Genres / All Types / Default sort row lead directly into six columns of 2:3 posters with titles below and the actual filtered item count. Genre choices use existing cached title metadata, type and sort use the library's saved data, and stable series identity preserves focus as the representative episode changes. Do not add a Library hero or stacked shortcut rails above this grid. Home and title detail retain dedicated artwork heroes; tvOS Search and Settings use the shared neutral canvas.

The Library options menu keeps collections, upcoming episodes, watch stats, tracker lists, sources, folders, tags, hidden items, bulk actions, and category management reachable on tvOS. Category names, visibility, and default restoration remain editable. The system Edit button and JSON category import remain iPhone/iPad-only because tvOS does not provide those SwiftUI APIs. The visible destination name is Library on every platform.

Use Nova's shared system button styles for interactive controls. iPhone/iPad use native materials and pearl-gray selection while tvOS uses the shared neutral focus style. Poster focus preserves image colors, aspect ratio, and row geometry. Cast and crew tiles always open a person's combined movie, television, and crew-credit filmography; do not reduce those pages to acting credits alone.

tvOS Settings uses six native push-navigation categories: Playback, Sources, Library, Experience, Accessibility, and Data & Privacy. Each destination owns one vertical scroll surface so the remote focus engine can reveal every control. Controls must edit real persistent preferences or invoke existing actions. Media servers, SMB, Live TV, Real-Debrid, add-ons, and supported accounts are consolidated under Sources. Snapshot Import previews a private Nova snapshot URL and does not imply a web server running on Apple TV. Record iCloud transfer and deletion results from observed local/cloud state, not from a requested sync alone.

Settings reset markers are additive. Nova owns local data and iCloud mirrors; updated iOS/tvOS clients consume per-category deletion boundaries and backup acknowledgements. A device-only reset pauses its category (History also pauses the composite Library mirror) until explicit Push/Pull. Shared resets redact setup backups; old clients cannot be forced to honor markers, so update them before relying on cross-device deletion. Never test deletion against personal data. URL snapshots remain bounded, previewed, cancellable, and category-selective; credentials are off by default. No UnifiedWorker schema changes are involved. Validate both app targets, policy fixtures, and remote focus; iCloud delivery requires an account-backed multi-device check.

Completed offline downloads remain playable from Settings → Offline Downloads using their local file; playback must not depend on the original network source being available.

Production AI/share calls use `https://api.sowensstudios.com/nova`. Verify both platform impact and the narrowest applicable tests/build.

SMB connections prefer Tailscale MagicDNS names (`*.ts.net`) over numeric addresses. Existing Tailscale IP shares upgrade in place when reverse DNS is available, preserving share IDs and Keychain credentials; IP and LAN names remain offline-compatible fallbacks. A personal default may be supplied only through machine-local `NovaConfig.json` as `preferredSMBServer` and must not be committed.

Trakt is not a connected provider. Users may export their data from Trakt and import the resulting ZIP in Settings → Accounts → Nova Tracker. Nova parses supported JSON/CSV files locally, previews the portable IMDb/TMDB records, deduplicates them, and submits confirmed watch state and ratings through the normal Nova Tracker contract. The app never uploads the ZIP or requires Trakt credentials.

Media integrations are data-only. On iOS, Addons → Media Tools can discover
UPnP devices, exchange NFO sidecars, evaluate smart playlists, import portable
M3U/M3U8 playlists, and install signed/checksummed declarative providers. Never
execute third-party modules or binaries in Nova.

Sonarr is an optional read-only Sources integration on iOS, iPadOS, and tvOS. Nova reads the
Sonarr v3 status, series statistics, 30-day calendar, and activity queue to show searchable series,
per-series availability, a grouped/filterable calendar, and detailed queue records. Missing or invalid
statistics remain unknown, and the last successful snapshot survives refresh failures. The queue
reports its first-50-record limit explicitly. Sonarr remains authoritative for acquisition and
quality upgrades. The server address is stored in app preferences, the API key stays in Keychain,
and Nova does not copy Sonarr's database or issue download-management commands.
## Nova Tracker service

Nova Tracker is first-party and zero-configuration at `https://api.sowensstudios.com/tracker`.
Settings → Accounts → Nova Tracker exposes synced stats, recent activity, custom lists,
and portable JSON backup. Title detail pages can add a title to any custom list.


Build numbers are automatic through shared Xcode schemes; `MARKETING_VERSION` remains manual.
The repo-owned `scripts/qa_build_number.py` reserves a locked project-wide number and stamps every
built app/extension/test plist before signing. It is vendored from Stocked; see
`scripts/QA_BUILD_NUMBER.md`. Use a shared scheme, not a direct `-target` build. Simulator builds/tests
require user authorization; reuse approval already granted for the current scope. On 2026-09-08,
the user approved simulator validation for this tvOS reference redesign. This approval is limited
to this pass and does not waive future approval or authorize uploads. Record actual build, test,
and visual-review outcomes separately; approval is not evidence that validation has passed.

Nova legacy sharing: UnifiedWorker owns the routing-only `frametv-ai-worker` shim. Existing iOS/tvOS clients produce encrypted snapshots and consume unchanged `/share/create` and `/share/fetch` responses. The shim rewrites to `/nova` through the existing service binding; authentication, one-time storage, expiry and limits stay in UnifiedWorker. Deploy only the shim after its routing test and dry-run. No client/database migration; current `/nova` URL is the fallback. Rollback version: `f23b1d3d-3bad-40c6-af98-95955c3a72c3`. Verify create/fetch and consumed-code failure through the legacy URL.

Title-detail secondary actions use a concrete ContentDetailActionButton boundary to reduce nested SwiftUI metadata expansion on tvOS. AddonDiskPersistence recreates its parent directory before atomic writes, including after purge/restore. No backup format or Worker changes. Native missing-directory recovery fixture passed; verify the title-detail crash on physical Apple TV before calling it resolved.

Catalog placeholder URLs must be created through `ContentID.catalogPlaceholderURL`. Add-on IDs are
provider-controlled and may contain URL delimiters or Unicode; never interpolate them into
`URL(string:)` and force unwrap while opening an iOS title detail.


### Apple TV glass controls (2026-09-10)
TVReferenceButtonStyle owns control padding, neutral glass surfaces, a bright focused surface with dark semantic foregrounds, and persistent selected outlines. Do not wrap these controls in a second decorative button background. Artwork uses TVArtworkButtonStyle to retain its image colors while showing a white focus frame. Respect Reduce Motion and Reduce Transparency. The floating TV navigation panel uses native glass; native menus inherit glass button styling. Title details use an artwork-first TV hero with Play, watched status, and a More menu retaining the secondary actions, plus a horizontal season selector. Keep the concrete ContentDetailActionButton boundary. Physical Apple TV review is still required for visual fidelity; a device-target build does not prove a pixel match.

### Watch Night (2026-09-14)
Library → Watch Night adds local viewing plans, runtime-fit search, three-title comparison, private spoiler notes, and estimated schedules. Plan JSON can be exported as a file on iPhone/iPad and previewed/imported by paste on either platform; Apple TV's View JSON is read-only. Notes and credentials never enter that portable document or Nova setup snapshots/iCloud mirrors. Library reset explicitly deletes this device's plans and notes. `WatchNightStore` owns protected, atomic `Application Support/watch-night.json`; unreadable data is preserved until recovery or explicit deletion. See `docs/WATCH_NIGHT_2026_09_14.md` for entry points and validation limits.

### Shared control polish (2026-09-14)
`Theme.Radius` and `Theme.Control` define control/artwork/navigation geometry and motion. Shared
styles distinguish persistent selection from temporary focus, hover, press, and disabled states.
Selected controls use checks/labels as well as borders. iOS keeps system-blue selection; tvOS uses
neutral glass with dark semantic labels on a white focus surface. Reduce Motion suppresses lift,
and Reduce Transparency / Increased Contrast use opaque surfaces. Icon controls stay circular.
Use semantic foregrounds inside controls, one surface owner, and artwork styles for image cards.
Settings and the iPhone home bar expose larger-text layouts and pointer feedback; Apple TV has a
separate Accessibility category. See `docs/NOVA_30_IMPROVEMENTS_2026_09_14.md` for the full feature,
polish, and validation record. Device visual and remote-focus acceptance remains separate from builds.

VLC audio/subtitle selection is based on the engine's current track indices. External downloads
have separate pending state, and Off/another choice/dismissal/stop supersede old requests. Register
external files without native forced selection, serialize registration, and confirm the applied
index before marking a provider track selected. `SubtitleSelectionPolicy.swift` is shared by both
app targets; the native fixtures cover request ordering and bounded subtitle sizing, while real
VLC registration remains a physical-device check.

September 14 validation: final generic iOS and tvOS builds passed; 37 Watch Night, 40 Sonarr, and 21 subtitle-selection native policy checks passed. No simulator/device visual run or real-provider mutation was performed. Full evidence and limits are in `docs/NOVA_30_IMPROVEMENTS_2026_09_14.md`.

### Second code/polish pass (2026-09-14)
Artwork and metadata caches now use bounded reads, collision-free keys, monotonic TTL/LRU rules,
and ownership-checked in-flight completion. Image downloads use capped temporary files and ImageIO
thumbnails, including disk hits; memory warnings cancel prefetch on iOS/tvOS. Canceled view loads
cannot paint over recycled cards. Disk caches are disposable: metadata v2 names may require one online warmup; existing artwork caches remain readable,
without migrating or changing the user's Library, notes, downloads, credentials, or provider contracts.
Tidy Up uses adaptive shared controls, review confirmations, truthful Hide/Keep feedback, and larger-text
layouts. Library Health has persistent selected checks, and artwork/loading motion follows system
accessibility and foreground state. See `docs/CODE_POLISH_PASS_2_2026_09_14.md` for 20 code changes,
10 polish changes, fixture evidence, and device-only acceptance limits.

Pass 2 verification: 60 native cache fixtures and generic iOS 1.7 (182) / tvOS 1.7 (183) builds passed. Device visuals and real-provider artwork downloads remain untested.

Legacy title metadata may migrate only after the domain validates its decoded content ID against the requested key; retain the original timestamp. Exact legacy artwork cache keys remain readable with bounded decoding. Unverifiable shelf keys cold-miss rather than guessing.


### Library/index code reliability pass 3 (2026-09-14)
`LibraryStore` now rejects oversized/unreadable saved files without overwriting them, rolls ordinary
failed saves back to its durable snapshot, and adopts cloud revisions only after local persistence.
A failed explicit library pull must not replace dependent queue/collection references. Collection
creation returns an optional persisted result; callers must handle failure before claiming success.
`LibraryFilePolicy` owns bounded reads/recreated atomic-write directories; `LibraryMutationPolicy`
owns keyed batch merges, queue reorders/projections and native-server reconciliation. Both helpers
belong to both app targets. Media indexing returns durable success to `MediaServerStore`; a failed
local commit must not advance its lastIndexed timestamp. Changed server content keys retain the
existing UUID/watch state and use a collection-reference bridge before library replacement. Duplicate
merges use the same bridge/commit helper and current rows, retaining alternate sources and queue order.
No persisted JSON fields or Worker contract changed. Only explicit valid cloud restoration/Settings
library reset clears a recovery guard; otherwise repair the saved file and relaunch. Older clients can
reintroduce unscoped server keys, so update both platform apps. Native fixtures use isolated adapters,
temporary files and independent UserDefaults suites; never run reset/recovery tests on user data.
See `docs/CODE_PASS_3_40_IMPROVEMENTS_2026_09_14.md` for counted changes and validation limits.


Media-server producer pass 3: `MediaServerIndexPolicy` owns URL/token-safe construction, same-origin
API redirects, 16 MiB response / 200,000 record / 1,024 library bounds, strict pagination and supported
video selection. Do not replace unknown provider totals with page size or accept an incomplete index.
Use Jellyfin/Emby user Views and valid ItemFields; legacy music+video selections retain their videos.
Native fallback IDs include kind + lowercased connection UUID + provider item ID. Authentication and
index tasks are generation-owned; local reconciliation must accept before success metadata publishes.
Unreadable connection settings are preserved and blocked; endpoint/provider/user changes cannot reuse
saved credentials implicitly. The 88 native producer checks use synthetic clients/settings, not live
servers. See `docs/CODE_PASS_3_MEDIA_INDEX_2026_09_14.md` for exact scope and provider references.


### Apple Watch companion (2026-09-14)
`Nova-watchOS` is a dependent watchOS 26 app embedded in `Nova-iOS`; companion ID must remain
`com.nova.app.ios`, watch bundle `com.nova.app.ios.watchkitapp`. Use the shared scheme and existing
QA numbering phases. WatchConnectivity DTOs live in `NovaWatchShared`; phone authority lives in
`Nova/Services/Watch`, watch cache/outbox/UI in `NovaWatch`. Only Foundation Watch Night models are
shared with watchOS; do not link UIKit/SMB/VLC/provider clients into the watch target.

Keep durable watch edits serialized until receipt, explicit-set rather than toggle, and epoch-bound.
Player/handoff requests expire after 20 seconds and never enter the offline outbox. Only actual
foreground registered AVPlayer/VLC models publish live controls. Open on iPhone requests Library
detail; it does not claim watch playback or start provider streams in the background. Never transfer
URLs, paths, credentials, or private notes. Preserve unreadable journals/cache; automatic snapshots
or cloud-deletion watermark reconciliation must not replace an unreadable original. Only explicit
local recovery/reset may do so. A different phone epoch requires correlated refresh after first sync.
Projection cancellation and revision checks precede cache publication; successful uncached-title
edits carry authoritative receipt metadata before removing optimistic state.

`docs/WATCHOS_APP_2026_09_14.md` records features, transport bounds, scope and physical limitations.
`scripts/run_watch_protocol_checks.sh` passes 60 optimized native checks. Generic watchOS and iOS
(embedded watch) builds passed; final iOS/watch 1.7 (196), tvOS 1.7 (193). Eight Apple Watch journeys
were added to the existing QA/checkbook registry and remain open for paired-device validation.
No simulators, devices, provider endpoints, or personal data were used for validation.
