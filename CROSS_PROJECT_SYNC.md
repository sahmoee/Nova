# Cross-project sync

- `UnifiedWorker`: Nova AI, encrypted share storage, QA, rate limits, and legacy shim.
- `site-repo`: public Nova pages, policies, support, and release links.
- User-configured media/tracking providers remain client integrations, not shared repo state.

Update Nova and UnifiedWorker together for API changes, additively where released clients exist. Update site-repo when public behavior or links change.
