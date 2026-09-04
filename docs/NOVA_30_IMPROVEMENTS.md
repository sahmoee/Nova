# Nova visual and loading refresh

Implemented September 3, 2026. This pass keeps Nova's single cinematic design
system and changes its shared tokens and infrastructure, so the improvements apply
to iPhone, iPad and Apple TV without screen-specific forks.

## Theme and presentation

1. Replaced the neutral-black canvas with a richer midnight-indigo black.
2. Gave elevated backgrounds a distinct cool-indigo depth.
3. Rebalanced elevated cards for clearer separation without opaque gray panels.
4. Replaced generic electric blue with an aurora-indigo interaction accent.
5. Added a cyan companion accent for focus and selected gradients.
6. Increased secondary-text contrast.
7. Increased tertiary-text contrast.
8. Increased quaternary-text contrast while preserving hierarchy.
9. Retinted the global background gradient to match the new palette.
10. Made the shared page background establish the primary foreground color.
11. Made the shared page background establish the app tint.
12. Made every custom page provide a matching native sheet background.
13. Added one scene-boundary theme modifier for system-owned UI.
14. Applied the scene theme to the entire iOS, iPadOS and tvOS hierarchy.
15. Kept the enforced cinematic dark appearance to prevent light-mode flashes.

## Networking and loading

16. Coalesced identical concurrent GET requests across shelves and screens.
17. Kept coalescing cancellation-safe for callers awaiting the same response.
18. Disabled unnecessary cookie storage for API traffic.
19. Disabled unnecessary credential persistence for API traffic.
20. Added a 15-second image request timeout.
21. Added a 30-second image resource timeout.
22. Disabled unnecessary image-session cookie storage.
23. Disabled unnecessary image-session credential persistence.
24. Cancelled active image work on a system memory warning.
25. Removed cancelled image tasks from the in-flight registry immediately.
26. Rejected unsuccessful HTTP image responses before decode.
27. Rejected oversized image payloads before decode to prevent memory spikes.
28. Preserved visual order while deduplicating image prefetches.
29. Bounded Discover grid/rail prefetch input to the first 24 visible-near items.
30. Bounded Library prefetch input to the first 24 visible-near items and made
    cached-image reload identity include its requested decode size.

## Validation

- `python3 scripts/audit_cinematic_ui.py`
- Generic iOS device build with code signing disabled
- Generic tvOS device build with code signing disabled

No simulator was launched. Performance budgets still require final measurement on
representative physical hardware with Instruments; builds prove integration, not a
specific runtime latency or memory number.
