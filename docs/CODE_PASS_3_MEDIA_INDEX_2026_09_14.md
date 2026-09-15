# Nova code pass 3 — media-server indexing

Date: 2026-09-14. This is the media-indexing half of the requested 40 new Nova code improvements. The 20 changes below are separate from the earlier Sonarr dashboard, VLC selection, shared-control polish, and cache work. No new UI feature is claimed.

## Exact 20 improvements

| # | Problem corrected and resulting behavior | Implementation evidence |
|---|---|---|
| 1 | Server addresses now normalize scheme/host/trailing slash without losing reverse-proxy paths. Unsupported schemes, embedded credentials, queries, fragments, invalid ports, traversal, and control characters fail validation. | `Nova/Services/MediaServerIndexPolicy.swift:23` — `normalizedBase` |
| 2 | Provider IDs and query values now pass through path components and `URLQueryItem`, preventing `?`, `#`, `+`, or `&` from changing request structure. Request and image/stream URL creation no longer force-unwrap interpolated strings. | `MediaServerIndexPolicy.swift:38`; `MediaServerClient.swift:94` — Jellyfin normalization and shared `decode` |
| 3 | Plex artwork/media paths must be relative to the configured server. They preserve its proxy prefix and replace the previous token query value; absolute hosts and traversal are rejected rather than receiving a saved token. | `MediaServerIndexPolicy.swift:54` — `resource`; `MediaServerClient.swift:146` — `plexItem` |
| 4 | API redirects are allowed only within the same scheme, host, and effective port. Redirected authentication/index requests cannot forward credentials to another origin or downgrade HTTPS. | `MediaServerIndexPolicy.swift:66` and `MediaServerRedirectDelegate`; client `decode` task delegate |
| 5 | JSON API bodies are streamed into a 16 MiB cap, with advertised-length checks and cancellation during accumulation. Only successful HTTP 200 responses are decoded, with authentication failures surfaced distinctly. | `MediaServerClient.swift:177` — `decode`; policy `maximumResponseBytes` |
| 6 | A missing provider collection is no longer treated as an empty library. Jellyfin requires `Items`; Plex requires `Metadata`/`Directory` or a compatible explicit zero count. Plex page-size mismatches fail decoding. | `MediaServerIndexPolicy.swift:134`, `:155`, `:167` — wire decoders |
| 7 | Pagination distinguishes a page's size from the complete library total. An absent total remains unknown and paging continues until an empty page, including when a server returns short pages. | policy `Pager`; `MediaServerClient.swift:115` — uses Plex `totalSize`, not `size` |
| 8 | Repeated or missing IDs, changed totals, incorrect returned offsets, early empty pages, and totals smaller than delivered records reject the snapshot. These failures cannot become a successful destructive reconciliation. | `MediaServerIndexPolicy.swift:85` — `Pager.accept` |
| 9 | Each index has a 200,000-record bound across libraries, each page is bounded, and discovery allows at most 1,024 unique library IDs. Records shared by multiple views normalize once rather than repeatedly adding identical server items. | policy limits, `selectedLibraries`, `Pager`; client `seenItems` in both adapters |
| 10 | Jellyfin/Emby discovery uses the authenticated user's Views endpoint instead of administrator-only virtual folders. The Items request uses real optional `ItemFields` values, removing invalid DTO-property names that could cause HTTP 400 and requesting the metadata actually consumed. | `MediaServerClient.swift:58`; `MediaServerIndexPolicy.swift:8` — `ProviderIds,MediaSources,MediaStreams,Path` |
| 11 | Video indexing filters out non-video sections while preserving older selections containing both video and music libraries. Known unsupported sections are pruned only after a successful snapshot; vanished IDs or music-only selections fail instead of silently switching to all video libraries. | `MediaServerIndexPolicy.swift:10`; both adapter discovery paths; `MediaServerStore.swift:160` |
| 12 | Plex looks for a media version with a playable part rather than dropping a title when its first version has none. Jellyfin video metadata likewise checks available media sources instead of assuming the first contains a video stream. | `MediaServerClient.swift:108`, `:149` |
| 13 | Native fallback content IDs include provider, connection UUID, and provider item ID, preventing unrelated servers with the same native ID from colliding. Invalid IMDb/TMDB identifiers do not override this identity. | `MediaServerClient.swift:99`, `:154`; policy `imdb`/`tmdb` validators |
| 14 | Jellyfin token authentication resolves `/Users/Me`; administrator-key fallback and Emby user discovery require an unambiguous user match. Password authentication requires a returned user ID, preventing a prior server's user from carrying into a new connection. | `MediaServerClient.swift:13`; `MediaServerStore.swift:84` — `connect` |
| 15 | Plex connection authentication decodes its identity document and requires a machine identifier, so an arbitrary HTTP 200 proxy/login page no longer counts as a validated server. | `MediaServerClient.swift:20`; `PlexIdentity` |
| 16 | Legacy connection JSON receives defaults for additive fields. Saved configuration is capped at 2 MiB and duplicate connection UUIDs are rejected. Unreadable original settings are retained and block ordinary overwrites instead of being silently replaced by an empty array. | `Nova/Models/MediaServerModels.swift:45`; `MediaServerStore.swift:37`, `:54` |
| 17 | Implicit saved-token reuse is restricted to the same normalized endpoint, provider, and user. Keychain read failures remain errors, and candidate settings encode successfully before credentials change. | `MediaServerModels.swift:61`; `MediaServerCredentialAccess`; store `save`/`connect` |
| 18 | Authentication has a per-connection operation generation. Removing, saving, or reconnecting a server retires older authentication, so a late result cannot restore a deleted server or replace newer credentials. | `MediaServerOperationGate`; `MediaServerStore.swift:84` and `:110` |
| 19 | Per-server indexing tasks have ownership guards, coalesce concurrent refreshes, and retire on configuration change/removal. Old completions cannot write results/errors or clear a newer spinner. Whole-library automatic refresh also coalesces and rechecks each connection's automatic-refresh preference before starting it. | `MediaServerStore.swift:64`, `:122`, `:146`, `:179` |
| 20 | Index timestamps/counts are committed only after `LibraryStore.reconcileMediaServer` accepts the snapshot. Local persistence and credential failures surface as refresh/removal errors. A failed requested local removal retains the connection and its credentials rather than reporting success. | `MediaServerStore.swift:110`, `:146`; `MediaServerError.localPersistence` |

References without a directory prefix in the table are in `Nova/Services/` unless explicitly under `Nova/Models/`.

## Ownership and compatibility

`MediaServerStore` remains the connection/refresh owner; credentials remain in Keychain. The injected credential and client interfaces permit isolated fixtures without touching real settings or secrets. `MediaServerClient` performs read-only provider discovery, indexing, and authentication. No provider library is changed, no downloads are requested, and no Worker endpoint or schema changes are involved.

The scoped native fallback is `<kind>:<lowercased connection UUID>:<provider item ID>`. Existing real IMDb/TMDB identifiers continue to take precedence. The parent pass owns the separate `LibraryStore` migration that retains existing saved UUIDs, watch state, alternate copies, and collection membership while these keys change; that preservation is not counted again here.

The new app source is `Nova/Services/MediaServerIndexPolicy.swift`, required by both iOS and tvOS targets. `scripts/MediaServerIndexChecks.swift` is native-only fixture code and is not part of either app target.

## Verification

**88 native checks passed**, compiling the production policy, provider client, connection models, and connection store in Swift 6 mode. The fixtures execute URL/selection/paging/wire-decoding policies and asynchronous store orchestration through an injected synthetic client, in-memory credential owner, and a unique temporary defaults suite. Rendering models and the Library/Keychain consumers have explicit native-only stand-ins. These fixtures do not claim to test actual Library persistence or execute the client's HTTP transport against a provider.

Coverage includes malformed and empty pages, missing/changing totals, duplicate IDs, short-page continuation, URL delimiters and traversal, origin checks, legacy field defaults, video/music selection migration, concurrent refresh coalescing, stale index/auth completion, local commit rejection, credential read failure, and preservation of corrupt settings. The field-list assertion is a narrow provider-contract regression check, not a live-server compatibility claim.

```sh
xcrun swiftc -swift-version 6 \
  Nova/Services/MediaServerIndexPolicy.swift \
  Nova/Services/MediaServerClient.swift \
  Nova/Services/MediaServerStore.swift \
  Nova/Models/MediaServerModels.swift \
  scripts/MediaServerIndexChecks.swift \
  -o /tmp/nova-media-index-checks
/tmp/nova-media-index-checks
```

`git diff --check` passed for the changed tracked sources. The parent agent owns final generic iOS/tvOS compilation and records those exact results in the combined pass manifest. No simulator, device install, personal-server request, or visual acceptance was performed in this subtask.

## Primary provider references

The Jellyfin contract corrections were checked against its official [user controller](https://raw.githubusercontent.com/jellyfin/jellyfin/master/Jellyfin.Api/Controllers/UserController.cs), [user Views controller](https://raw.githubusercontent.com/jellyfin/jellyfin/master/Jellyfin.Api/Controllers/UserViewsController.cs), [Items controller](https://raw.githubusercontent.com/jellyfin/jellyfin/master/Jellyfin.Api/Controllers/ItemsController.cs), and [ItemFields enum](https://raw.githubusercontent.com/jellyfin/jellyfin/master/MediaBrowser.Model/Querying/ItemFields.cs). Emby documents the corresponding [user Views endpoint](https://dev.emby.media/reference/RestAPI/UserViewsService/getUsersByUseridViews.html). Plex exposes its [server API reference](https://developer.plex.tv/pms/) and [server URL commands](https://support.plex.tv/articles/201638786-plex-media-server-url-commands/).

## Remaining limits

Actual authentication, paging, redirects, proxy layouts, and playback need an account-backed check on the user's Jellyfin/Emby/Plex versions. A same-origin-only API redirect policy deliberately rejects cross-origin proxy handoffs; configure the final server address in that case. A library changing during paging may require retrying rather than accepting a partial snapshot. The index remains in memory until a complete snapshot is available, within the explicit bounds; this pass does not implement a disk-backed incremental index.

Keychain, UserDefaults, and Library files are different stores, not one transaction. Encoding and local acceptance gates prevent false success, but they do not guarantee recovery from a power loss between every store write. If requested indexed-item removal succeeds and the subsequent Keychain deletion fails, the connection remains and can be reindexed; the error is visible. Library/file rollback fixtures and cloud-delivery limitations are recorded in the parent pass. Corrupt connection data is preserved for recovery rather than automatically guessed or deleted.
