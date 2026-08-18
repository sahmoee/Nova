# Cross-project sync

Also apply the ten additive cross-project safeguards in `PROJECT_GUIDE_ADDITIONS.md`; existing ownership and compatibility rules remain authoritative.

- `UnifiedWorker`: Nova AI, encrypted share storage, QA, rate limits, and legacy shim.
- `site-repo`: public Nova pages, policies, support, and release links.
- User-configured media/tracking providers remain client integrations, not shared repo state.

Update Nova and UnifiedWorker together for API changes, additively where released clients exist. Update site-repo when public behavior or links change.
Nova's `/titles` response always retains the legacy flat `titles` array; multi-collection requests may also include additive named `collections` previews.

Trakt list importing is client-owned and uses Trakt/TMDB directly. Only the optional Nova Tracker destination crosses into `UnifiedWorker`; it reuses the existing additive `v1/status` contract and requires no Worker schema change.

Nova QA is available only during a ten-minute `Joo` passcode window. Unlocked iOS/iPadOS devices merge app-scoped tickets from every Nova device through `POST /_unified/qa/tickets/sync` before retrying local writes. Mac targets do not expose in-app QA.
## Nova Tracker contract

`UnifiedWorker` owns the `/tracker/v1/*` contract and the `nova_tracker` D1 schema.
Nova owns the Keychain token, iCloud-KVS account link, offline delta cache, and Tracker UI.
Tracker changes must remain additive so installed clients continue syncing.
