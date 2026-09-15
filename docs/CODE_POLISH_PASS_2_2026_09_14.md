# Nova — second pass: 20 code improvements + 10 polish improvements

This is additional to `NOVA_30_IMPROVEMENTS_2026_09_14.md`. Scope: shared artwork/metadata caches and Library maintenance on iOS/iPadOS/tvOS. It adds no provider, Worker, account, playback-history, or user-library schema. The previous pass remains intact.

## 20 code improvements

| # | Observed issue → implemented change | Owner |
|---|---|---|
| 1 | Wall-clock changes altered in-memory expiration → monotonic uptime TTL. | TTLCache |
| 2 | Small cache capacities could evict zero entries and grow indefinitely → clamped capacity with real LRU eviction. | TTLCache |
| 3 | Replacing an existing value evicted unrelated titles → overwrite in place. | TTLCache |
| 4 | A caller could miss, then redundantly start a request after another caller filled the cache → coalesced loads recheck fresh values. | TTLCache |
| 5 | An old flight completing after reset could clear a replacement or repopulate data → UUID-owned completion and cache publication, consumed by catalog search and shelf loads; shelf disk writes run inside the canceled producer and returned UI results carry a generation guard. | TTLCache / CatalogService / ShelfLoader |
| 6 | Punctuation-normalized disk keys collided and long keys exceeded filename limits → versioned SHA-256 names over exact UTF-8 keys. | DiskJSONCache |
| 7 | Disk cache reads decoded arbitrary-size files → stat preflight plus a bounded actual FileHandle read. | DiskJSONCache |
| 8 | Corrupt, expired, or far-future entries were retried indefinitely → reject and remove unusable cache files. | DiskJSONCache |
| 9 | OS removal of the cache directory made later saves silently fail forever → recreate directory before atomic writes. | DiskJSONCache |
| 10 | Offline metadata had no storage budget and broad prefix deletion → byte/count/LRU maintenance and regular-owned-JSON-only clearing. | DiskJSONCache |
| 11 | Invalid or extreme image dimensions could trap during integer conversion or allocate excessive pixels → shared finite 64–4096 pixel normalization and checked pixel costs. | ArtworkCachePolicy |
| 12 | Artwork bodies were fully buffered before the 25 MiB check → temporary-file download, transfer-size cancellation, file-size verification, and removal of temporary files. | ImageLoader |
| 13 | Corrupt cached artwork and failed thumbnail decoding used full-resolution UIImage fallbacks → bounded ImageIO downsampling on disk/network paths; no full-resolution fallback. | ImageLoader |
| 14 | A retired image task could erase a replacement and refill memory after purge → flight UUID ownership and cancellation checks before publication. | ImageLoader |
| 15 | Memory pressure canceled current transfers but left prefetch work able to refill them; tvOS had no observer → cancel prefetch too and handle memory warnings on both platforms. | ImageLoader |
| 16 | Broken artwork retried on every card recreation → bounded 20-second negative cache, cleared by memory purge. | ImageLoader |
| 17 | Artwork disk eviction ran only at launch → periodic background maintenance during long sessions, every 16 cache fills. | ImageLoader |
| 18 | Artwork eviction could remove directories/symlinks and counted failed deletions as freed bytes → regular JPEG-file ownership checks and successful-removal accounting. | ImageLoader |
| 19 | A canceled image request could paint over a recycled SwiftUI card → normalized load identity, request token, cancellation check, and identity-matched rendering. | CachedAsyncImage |
| 20 | Canceled metadata/source work still emitted fallback snapshots or cached incomplete results → cancellation guards before progressive callbacks, fallback, and cache publication. | CatalogService |

The image budget is a periodic eviction target; it may temporarily exceed 300 MiB between sweeps. Each network response is capped at 25 MiB, allowing a delegate callback's in-flight chunk. Disk metadata budgets default to 96 MiB/1,024 entries per owner and 8 MiB per entry. A cache miss remains nonfatal.

## 10 polish improvements

| # | Visible result | Entry point |
|---|---|---|
| 1 | Artwork fades respect Reduce Motion and never briefly show the previous card's title art. | All CachedAsyncImage consumers |
| 2 | Loading shimmer responds to live Reduce Motion changes and stops while the app is backgrounded. | Shared loading placeholders |
| 3 | Library Health uses legible scrolling tabs with persistent checks, shared focus/hover surfaces, and selected accessibility traits. | Settings → Library Health |
| 4 | Tidy Up actions use the shared button geometry, focus/hover feedback, and minimum target size instead of tiny custom capsules. | Settings → Library → Library Health → Tidy Up |
| 5 | Tidy Up actions wrap in adaptive columns with space for larger text. | Tidy Up cards |
| 6 | Long titles wrap; progress and last-played information have distinct, readable lines; artwork uses the shared thumbnail radius. | Tidy Up cards |
| 7 | Review count, context-aware completion text, and Show Kept Titles make session progress clear and reversible. | Tidy Up |
| 8 | Remove and Clear Progress present the affected title and an explicit confirmation with Cancel. | Tidy Up actions |
| 9 | VoiceOver actions include the title and outcome; decorative posters are excluded and metadata is grouped. | Tidy Up cards |
| 10 | The old Archive label now says Hide, explains where the title remains accessible, and all actions show a result message. | Tidy Up |

## Compatibility and ownership

Nova owns these disposable caches; TMDB/add-on/media artwork endpoints remain producers, and both app targets consume the same implementations. No deployment, Worker rollout, token change, user-data migration, or remote mutation is required. Offline library/playback behavior remains authoritative.

Hashed v2 filenames intentionally do not guess which original key produced an ambiguous legacy cache file. Existing single-title metadata can migrate offline only when one of its explicit provider identities and content type matches the requested key, even if hydration later added a preferred IMDb ID; the original expiration is retained. Shelf caches and unverifiable metadata may need one online fetch to warm the new cache; legacy cache files remain subject to normal expiry/eviction. Existing artwork caches are reused by reconstructing their exact former URL-and-size key, with the same bounded decode checks. Library records, private notes, downloads, and credentials are unaffected. Downgrading creates cache misses rather than corrupting user data.

## Verification

- 60 new native checks pass against the actual TTL, disk-cache, and artwork policy implementations. Fixtures use a private temporary directory, injected clocks, and gated concurrent producers; no personal data is used.
- Swift syntax and project property-list validation passed.
- Generic iOS **1.7 (182)** and tvOS **1.7 (183)** builds passed. Logs: `/tmp/nova-pass2-ios-20260914.log` and `/tmp/nova-pass2-tvos-20260914.log`. Existing AMSMB2 resource warnings were reported; no simulator or device was launched.
- No simulator/device run, installation, live-provider test, visual fidelity assertion, or measured frame-rate claim.

Command: `swiftc -parse-as-library Nova/Services/TTLCache.swift Nova/Utilities/DiskJSONCache.swift Nova/Services/ArtworkCachePolicy.swift scripts/CacheReliabilityChecks.swift -o /tmp/nova-cache-checks && /tmp/nova-cache-checks`.

Apple references for implementation constraints: [downloaded temporary files](https://developer.apple.com/documentation/foundation/urlsessiondownloaddelegate/urlsession(_:downloadtask:didfinishdownloadingto:)), [ImageIO thumbnail size](https://developer.apple.com/documentation/imageio/kcgimagesourcethumbnailmaxpixelsize). Native URLSession delegate behavior, large real images, VoiceOver, pointer movement, and physical Apple TV focus still need on-device acceptance.

Independent code review caught and verified fixes for retired shelf publication (including the initial actor-hop window), enriched legacy metadata identities, and Tidy Up navigation. The final generic builds include those fixes.
