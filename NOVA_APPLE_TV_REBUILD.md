# Nova Apple TV rebuild

Nova now has one cinematic presentation system shared by iPhone, iPad, and tvOS.
The media, playback, library, source, account, tracking, and AI layers remain intact;
this rebuild replaces their presentation and interaction language.

## Forty implemented design changes

1. Near-black, artwork-first application canvas.
2. Neutral elevation instead of colored dashboard panels.
3. One electric-blue interactive accent family.
4. Full-bleed Home artwork beneath the safe area.
5. Layered hero scrims for readable type on any artwork.
6. Oversized rounded hero typography.
7. Compact uppercase hero eyebrow labels.
8. Dedicated Play/Resume hero action.
9. Dedicated More Info hero action.
10. Persistent Home search chrome.
11. Persistent Home customization chrome.
12. Persistent viewing-profile chrome.
13. Automatic hero rotation with motion reduction support.
14. Compact carousel page indicators.
15. Native tab navigation on iPhone and tvOS.
16. Persistent sidebar navigation on iPad.
17. Independent navigation history for every destination.
18. Home, Browse, Library, Ask Nova, and Settings naming hierarchy.
19. Dark translucent button rest states.
20. Saturated blue gradient button focus states.
21. Cool hairline borders on every shared control family.
22. Rounded-rectangle geometry for rows and primary actions.
23. Capsule geometry for filters and compact actions.
24. Circular geometry for icon-only actions.
25. Focus lift, glow, scale, and z-order on tvOS.
26. Press compression on touch controls.
27. Landscape Continue Watching cards.
28. Remaining-time badges and persistent progress bars.
29. Poster and landscape rails selected by content purpose.
30. Context actions for play, queue, favorite, watched, download, and hide.
31. Large rounded section typography with trailing actions.
32. Edge-to-edge horizontal rails with focus breathing room.
33. Reactive artwork backdrops isolated by destination.
34. Deterministic utility headers that never leak media artwork.
35. Full-bleed title-detail artwork with layered blur fallback.
36. Monochrome material-based Settings groups.
37. Unified cinematic empty, loading, failure, and setup states.
38. Floating glass mini-player with artwork and progress.
39. Player controls built from the shared chip and icon language.
40. Dynamic Type, Reduce Motion, safe-area, orientation, and remote-focus adaptation.

## Twenty additional major additions

41. Editorial Top Picks now render with oversized ranked numerals.
42. Focused media artwork gains a centered Play/Info affordance.
43. Focused cards gain an artwork-bottom readability scrim.
44. Available resolution metadata appears as a compact quality badge.
45. Card titles brighten and lift with the focused artwork.
46. Horizontal shelves allow focused cards to grow beyond scroll bounds.
47. Quick-access destinations use the same blue focus ring and glow as media.
48. Search is recast as the broader Browse destination.
49. Browse search uses a floating ultra-thin material field.
50. Browse search gets an explicit blue active-focus border.
51. Browse search gets a soft active-focus bloom instead of a flat box.
52. The iPhone tab bar is forced into cinematic dark material appearance.
53. tvOS receives an app-wide artwork-accent ambient light field.
54. The iPad sidebar now includes persistent profile/account chrome.
55. Mini-player icon actions use the shared circular focus system.
56. Mini-player Resume uses Nova's blue gradient action treatment.
57. Resume/Restart playback prompts inherit the title's artwork backdrop.
58. Resume/Restart choices sit on a centered cinematic glass panel.
59. Ranked, progress, source, favorite, watched, and quality overlays coexist semantically.
60. All new motion and focus additions obey Reduce Motion and accessibility labels.

## Loading, speed, sources, and playback

61. Loading uses a branded breathing media glyph instead of a generic spinner.
62. Loading animation automatically stops expanding under Reduce Motion.
63. Stream discovery reports completed source count while it runs.
64. Source discovery shows three stable skeleton rows to prevent layout jumping.
65. Long-running source discovery exposes an immediate Cancel action.
66. Stream loading is keyed to title and episode identity.
67. Stale progressive callbacks are ignored after task cancellation.
68. Completed source-search work is ignored when its screen task is cancelled.
69. Stream resolution ignores completion after cancellation.
70. Failed stream resolution ignores errors caused by cancellation.
71. Reload clears stale streams, resolution state, and failover state.
72. Progressive streams remain visible as each addon finishes.
73. Source progress includes a combined completion bar.
74. Source rows retain individual latency and result counts.
75. Group and Filter are condensed into capsule controls.
76. Resolving rows identify Opening versus automatic failover.
77. Source cards use shared glass, blue focus rings, glow, and lift.
78. Playback loading inherits the title artwork and cinematic scrim.
79. Player accessory actions use the shared circular focus system.
80. Prepared next episodes are directly playable from the iOS accessory bar.

## Code, resuming, and option simplification

81. VLC always uses one Apple-style transport hierarchy.
82. The legacy VLC overlay choice is removed from visible settings.
83. Appearance explains the unified Apple Player/VLC interface.
84. The unused classic library-detail implementation is removed.
85. Legacy visual preferences remain decode-compatible without controlling presentation.
86. Resume and restart share one artwork-backed decision surface.
87. Automatic next-episode preparation is cancelled when playback disappears.
88. Prepared next playback reuses the existing library/progress pipeline.
89. Playback failure retains one-tap retry, alternate engine, and stream failover.
90. Dead streams are removed from the current candidate set immediately.
91. Auto-failover never retries a stream already marked dead.
92. Previously successful streams remain promoted for resume continuity.
93. Real-Debrid availability refinement remains asynchronous and non-blocking.
94. Stream filters are evaluated in one ordered predicate pipeline.
95. Full filter controls stay collapsed until explicitly requested.
96. Compact quality and cached controls cover the common source decisions.
97. Settings no longer expose redundant Home, Library, detail, tab, component, or player-overlay styles.
98. Presentation ownership was audited across all sheets, covers, and popovers.
99. Shared loading, empty, error, button, focus, and material primitives remain the default for every page.
100. All 184 Swift files and all 54 presentation sites were included in the static UI audit.

## Non-negotiable invariants

- Local library and playback state remain authoritative.
- All existing destinations and media-management actions remain available.
- No Apple branding, artwork, or proprietary assets are copied.
- Visual similarity comes from hierarchy, motion, materials, focus, and layout.
- The visible app no longer offers a legacy component-style escape hatch.
