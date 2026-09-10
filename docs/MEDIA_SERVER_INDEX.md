# Media-server index

Nova maintains one local, searchable library across direct links, SMB, Jellyfin, Plex and Emby. It
does not copy media files or make a remote server the owner of watch state.

## Ownership and data flow

- `MediaServerStore` persists non-secret connection settings, runs one cancellable refresh at a time,
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
Removing a connection always removes its Keychain token; removing its indexed rows is an independent
choice. A later reconnect can rebuild the index.

The first successful refresh discovers server libraries and selects all of them. The editor then lets
the user choose a subset and reindex. Server deletions remove only that server location. If the same
title is still available through another server or source, Nova promotes that alternate instead.

## Compatibility and rollout

All persisted fields are additive and decode with empty defaults. Older libraries remain readable.
There is no Worker or public-site contract change. The client ships as one coordinated iOS/tvOS
change; either platform can create or refresh connections synced through the existing app backup,
while secrets follow the existing Keychain behavior.

Validation should cover Jellyfin, Plex and Emby authentication; empty and large libraries; movie and
episode identity; library selection; cancellation/offline retry; server-side deletion; duplicate
content across two servers; playback and artwork URLs; iOS compact/regular layouts; and tvOS remote
focus and Back-menu behavior.
