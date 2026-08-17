# Cross-project sync

- `UnifiedWorker`: Nova AI, encrypted share storage, QA, rate limits, and legacy shim.
- `site-repo`: public Nova pages, policies, support, and release links.
- User-configured media/tracking providers remain client integrations, not shared repo state.

Update Nova and UnifiedWorker together for API changes, additively where released clients exist. Update site-repo when public behavior or links change.
Nova's `/titles` response always retains the legacy flat `titles` array; multi-collection requests may also include additive named `collections` previews.

Nova QA is available only during a ten-minute `Joo` passcode window. Unlocked iOS/iPadOS devices merge app-scoped tickets from every Nova device through `POST /_unified/qa/tickets/sync` before retrying local writes. Mac targets do not expose in-app QA.
