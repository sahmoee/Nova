# Media-server index

Nova maintains one local, searchable library across direct links, SMB, Jellyfin, Plex and Emby. It
does not copy media files or make a remote server the owner of watch state.

## Ownership and data flow

- `MediaServerStore` persists non-secret connection settings, coalesces one owned refresh per server,
  and records per-server counts, dates and failures.
- `MediaServerClient` authenticates and reads provider libraries. Jellyfin and Emby use their public
  user/items APIs; Plex uses its library sections and metadata APIs.
- Tokens are stored under per-connection Keychain accounts. Passwords are exchanged for tokens and
  are not persisted.
- `LibraryStore` reconciles normalized `MediaItem` rows atomically. IMDb/TMDB identity merges matching
  content; `alternateSources` retains other playable locations. User IDs, favorites, tags, hidden
  state, subtitles and progress survive refreshes.
- Home, Library, local search, Spotlight and widgets consume `LibraryStore`, so newly indexed content
  appears everywhere without a provider-specific UI fork.

## Refresh and recovery

Automatic refresh runs when Nova's environment starts and only for enabled connections. Manual
Refresh is always available. Provider errors retain the last good local index and display the error.
Removing a connection attempts to remove its Keychain token; a reported failure retains the
connection for recovery. Removing indexed rows is an independent choice. A later reconnect can
rebuild the index. Index dates advance only after local reconciliation succeeds.

The first successful refresh discovers supported video libraries and selects all of them. The editor then lets
the user choose a subset and reindex. Server deletions remove only that server location. If the same
title is still available through another server or source, Nova promotes that alternate instead.

## Compatibility and rollout

Additive connection fields decode with defaults; identity, kind, name and address remain required.
Oversized, malformed or duplicate-identity connection data is preserved and ordinary writes are
blocked until recovery. Older valid libraries remain readable.
There is no Worker or public-site contract change. The client ships as one coordinated iOS/tvOS
change; either platform can create or refresh connections synced through the existing app backup,
while secrets follow the existing Keychain behavior.

Validation should cover Jellyfin, Plex and Emby authentication; empty and large libraries; movie and
episode identity; library selection; cancellation/offline retry; server-side deletion; duplicate
content across two servers; playback and artwork URLs; iOS compact/regular layouts; and tvOS remote
focus and Back-menu behavior.

## Index reliability (2026-09-14 pass 3)

`MediaServerIndexPolicy` owns URL validation, encoded paths/query values, same-origin API redirects,
library selection and strict raw-record pagination. API responses are bounded at 16 MiB, each index
at 200,000 records, and discovery at 1,024 libraries. Missing totals remain unknown until an empty
page; inconsistent or repeated pages fail without replacing the last good index. Jellyfin/Emby
use user Views and valid optional ItemFields. Legacy selections containing video and non-video
sections keep their selected videos; absent libraries and non-video-only selections require review.

Fallback content IDs are `<kind>:<lowercased connection UUID>:<provider item ID>`. Authentication
and index generations prevent removed/edited connections being restored by late callbacks. Saved
tokens are implicitly reused only for the same normalized endpoint, provider and user. See
`CODE_PASS_3_MEDIA_INDEX_2026_09_14.md` for the exact 20 changes, 88 native checks, primary provider
references, and live-integration/persistence limits. The combined pass records final device-target
build results separately from runtime acceptance.
