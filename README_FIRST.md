# Read me first

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

Nova uses Apple platform styling throughout: a neutral black Apple TV canvas, standard San Francisco typography, semantic system colors, native materials, and compact system controls. iPhone and iPad use system blue for actions and selection. tvOS uses the native neutral white focus surface with dark text and a restrained lift. Media artwork supplies the color; app chrome must not introduce a separate brand palette, artwork-derived tint, colored glow, or decorative background gradient. Keep top-level controls condensed.

Primary navigation is Home, Search, Library, and Settings. Smart Search is integrated inside Search; `AppTab.ai` and `nova://ai` exist only for compatibility and must route into Search. iPhone uses the shared floating `NovaHomeBar`, iPad uses its sidebar, and tvOS uses the Back menu. tvOS Settings uses a five-category native directory; selecting a category pushes one independently scrolling destination. See `docs/UI_UX_REDESIGN_2026_09_09.md`.

tvOS navigation is a floating Back menu with Remote, Home, Search, Library, and Settings. A root page's heading or the remote Back button opens it; Back closes the open menu. Pushed destinations retain native Back navigation. RootView keeps visited sections mounted while excluding inactive sections from interaction and accessibility. The root-only Now Playing bar follows the same menu behavior. TVPageHeading and TVReferenceStyle own the shared television heading and geometry. Preserve the iPhone bottom tab bar and iPad sidebar independently of tvOS changes.

Home is an artwork-first streaming storefront. On tvOS, the hero leads with title artwork (or a text fallback), real metadata, a short synopsis, Play/Resume, Up Next, information, circular page indicators, and landscape Continue Watching cards. Source setup, source health, profile editing, and shelf customization belong in Settings instead of Home. The iPhone/iPad feed retains its own hero, rails, and Discover composition. Use Nova's live artwork and destinations; do not embed reference-screen branding, sample titles, or imagery.

The Home hero extends beneath the top safe area. Its visible artwork is aspect-fit so the complete composition remains visible without stretching; a restrained full-bleed copy may sit behind it to fill the canvas when source aspect ratios differ.

Reactive artwork remains scoped to the destination that owns it: selections must not leak between Library, Search/Discover, Collections, and AI. Preserve the iPhone/iPad artwork behavior. tvOS Library is an explicit exception to the artwork-header layout: its compact heading and All Genres / All Types / Default sort row lead directly into six columns of 2:3 posters with titles below and the actual filtered item count. Genre choices use existing cached title metadata, type and sort use the library's saved data, and stable series identity preserves focus as the representative episode changes. Do not add a Library hero or stacked shortcut rails above this grid. Home and title detail retain dedicated artwork heroes; tvOS Search and Settings use the shared neutral canvas.

The Library options menu keeps collections, upcoming episodes, watch stats, tracker lists, sources, folders, tags, hidden items, bulk actions, and category management reachable on tvOS. Category names, visibility, and default restoration remain editable. The system Edit button and JSON category import remain iPhone/iPad-only because tvOS does not provide those SwiftUI APIs. The visible destination name is Library on every platform.

Use Nova's shared system button styles for interactive controls. iPhone/iPad use native materials and system blue selection while tvOS uses the shared neutral focus style. Poster focus preserves image colors, aspect ratio, and row geometry. Cast and crew tiles always open a person's combined movie, television, and crew-credit filmography; do not reduce those pages to acting credits alone.

tvOS Settings uses five native push-navigation categories: Playback, Sources, Library, Experience, and Data & Privacy. Each destination owns one vertical scroll surface so the remote focus engine can reveal every control. Controls must edit real persistent preferences or invoke existing actions. Media servers, SMB, Live TV, Real-Debrid, add-ons, and supported accounts are consolidated under Sources. Snapshot Import previews a private Nova snapshot URL and does not imply a web server running on Apple TV. Record iCloud transfer and deletion results from observed local/cloud state, not from a requested sync alone.

Settings reset markers are additive. Nova owns local data and iCloud mirrors; updated iOS/tvOS clients consume per-category deletion boundaries and backup acknowledgements. A device-only reset pauses its category (History also pauses the composite Library mirror) until explicit Push/Pull. Shared resets redact setup backups; old clients cannot be forced to honor markers, so update them before relying on cross-device deletion. Never test deletion against personal data. URL snapshots remain bounded, previewed, cancellable, and category-selective; credentials are off by default. No UnifiedWorker schema changes are involved. Validate both app targets, policy fixtures, and remote focus; iCloud delivery requires an account-backed multi-device check.

Completed offline downloads remain playable from Settings → Offline Downloads using their local file; playback must not depend on the original network source being available.

Production AI/share calls use `https://api.sowensstudios.com/nova`. Verify both platform impact and the narrowest applicable tests/build.

SMB connections prefer Tailscale MagicDNS names (`*.ts.net`) over numeric addresses. Existing Tailscale IP shares upgrade in place when reverse DNS is available, preserving share IDs and Keychain credentials; IP and LAN names remain offline-compatible fallbacks. A personal default may be supplied only through machine-local `NovaConfig.json` as `preferredSMBServer` and must not be committed.

Trakt is not a connected provider. Users may export their data from Trakt and import the resulting ZIP in Settings → Accounts → Nova Tracker. Nova parses supported JSON/CSV files locally, previews the portable IMDb/TMDB records, deduplicates them, and submits confirmed watch state and ratings through the normal Nova Tracker contract. The app never uploads the ZIP or requires Trakt credentials.

Media integrations are data-only. On iOS, Addons → Media Tools can discover
UPnP devices, exchange NFO sidecars, evaluate smart playlists, import portable
M3U/M3U8 playlists, and install signed/checksummed declarative providers. Never
execute third-party modules or binaries in Nova.
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


### Apple TV glass controls (2026-09-10)
TVReferenceButtonStyle owns control padding, neutral glass surfaces, a bright focused surface with dark semantic foregrounds, and persistent selected outlines. Do not wrap these controls in a second decorative button background. Artwork uses TVArtworkButtonStyle to retain its image colors while showing a white focus frame. Respect Reduce Motion and Reduce Transparency. The floating TV navigation panel uses native glass; native menus inherit glass button styling. Title details use an artwork-first TV hero with Play, watched status, and a More menu retaining the secondary actions, plus a horizontal season selector. Keep the concrete ContentDetailActionButton boundary. Physical Apple TV review is still required for visual fidelity; a device-target build does not prove a pixel match.
