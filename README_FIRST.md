# Read me first

Nova is a local-first iOS/iPadOS/tvOS personal-media app. User libraries and progress are authoritative; remote metadata, AI, tracking, and sharing are optional. Start in `Nova/App`, then the relevant `Nova/Services` or `Nova/Views` area. Keep credentials in Keychain, never source control.

Nova's primary UI is one cinematic Apple TV-inspired system: near-black artwork-led canvases, compact translucent control bars, restrained blue focus/accent states, consistent glass summary surfaces, and content-first poster rails or grids. Keep top-level controls condensed; never rebuild stacked oversized filter rows when a compact menu plus segmented control preserves the same functions.

Home is an artwork-first streaming storefront: a full-bleed rotating title hero fading directly into the black canvas, circular page indicators, compact landscape Continue Watching cards, and a two-column visual Discover grid. Use Nova's live artwork and destinations; do not embed reference-screen branding or imagery. The existing tab bar is a separate invariant and must not be restyled as part of Home feed work.

The Home hero extends beneath the top safe area. Its visible artwork is aspect-fit so the complete composition remains visible without stretching; a restrained full-bleed copy may sit behind it to fill the canvas when source aspect ratios differ.

Every media-bearing destination uses a full-width reactive artwork header. Focusing a title on tvOS or tapping it on iPhone/iPad updates only that destination's backdrop with a restrained crossfade; Search/Discover, My Nova, Collections, and AI retain independent header selections so artwork never leaks between pages. Home and title detail retain their dedicated full-artwork heroes. Utility pages without media do not invent decorative artwork, and this reactive system never owns or alters the tab bar.

Library category names, visibility, and default restoration remain available on tvOS. The system Edit button and JSON document import are iPhone/iPad-only because tvOS does not provide those SwiftUI APIs.

Use Nova's shared button styles for every interactive control: dark translucent glass at rest, a saturated blue gradient/highlight when selected or focused, a fine cool border, and the semantic mockup shape (rounded rectangle for rows, capsule for filters, circle for icon-only actions). Cast and crew tiles always open a person's combined movie, television, and crew-credit filmography; do not reduce those pages to acting credits alone.

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
currently require the user's approval; this setup does not authorize uploads.
