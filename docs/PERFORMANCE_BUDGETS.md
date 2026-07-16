# Astra Performance Budgets

Measurable limits for the experiences users feel most. These are targets for release
builds on representative hardware (iPhone 12-class, A12 Apple TV, iPad Air-class).
They are mirrored in code as `PerformanceBudgets` (Utilities) and surfaced in the Debug
Report so regressions are visible.

| Metric | Budget | Measured via | Notes |
|---|---|---|---|
| Cold launch → first frame | ≤ 1200 ms | OSSignpost `launch` | Time from process start to Home first paint. |
| Home shelves interactive | ≤ 800 ms | OSSignpost `home` | After launch; shelves scrollable with placeholders. |
| Search first results | ≤ 900 ms | OSSignpost `search` | Predictive suggestions ≤ 300 ms; full results ≤ 900 ms. |
| Poster decode (each) | ≤ 40 ms | OSSignpost `poster` | Off the main thread; cached decode ≤ 8 ms. |
| Stream resolution (addon→playable) | ≤ 6000 ms | OSSignpost `stream` | Per-source bounded; auto-fail-over on timeout. |
| Player startup (tap → playing) | ≤ 3000 ms | OSSignpost `player` | Cached/direct ≤ 1500 ms. |
| Steady-state memory (browsing) | ≤ 350 MB | Xcode Instruments | Excludes active video decode buffers. |
| Dropped frames while scrolling | < 1% | Instruments / hitch rate | 60/120 Hz as supported. |

## How they're enforced
- **Signposts:** the metrics above emit `OSSignposter` intervals (subsystem `com.astra.app`)
  so they can be captured in Instruments and summarized in the Debug Report.
- **Debug Report:** includes the most recent sampled durations (no tokens, no full URLs).
- **CI note:** `release_check.sh` does not measure timing (no Apple SDK on Linux). Timing
  budgets must be validated on-device with Instruments before a release.

## When a budget is exceeded
1. Confirm it reproduces on a representative device (not just Simulator).
2. Capture an Instruments trace filtered to the relevant signpost.
3. Prefer caching, bounded concurrency, and off-main-thread work over feature removal.
