# Nova: 50 implemented improvements

Fifty changes are implemented in the local working tree:

- **1-25: core/playback/network reliability**, numbered in
  [NOVA_RELIABILITY_25_2026_09_05.md](NOVA_RELIABILITY_25_2026_09_05.md).
- **26-50: UI/UX**, corresponding to rows 1-25 in
  [NOVA_UI_UX_25_2026_09_05.md](NOVA_UI_UX_25_2026_09_05.md).

Highlights: safer offline download lifecycle and file ownership; reliable resume data; bounded
provider retries; cancellable source discovery/resolution; cached-only automatic selection and
failover; protected naming drafts; subtitle search/identity; responsive errors and offline queue UI.
The Apple TV-inspired design and shared header/tab geometry are preserved.

## Final validation

| Validation | Result |
| --- | --- |
| iPhone/iPad generic-device build-for-testing | Build 76 passed; app, widget and test bundle |
| Apple TV generic-device build | Build 77 passed |
| Native core/playback/retry checks | 58 passed |
| Native UI policy checks | 17 passed |
| Existing cinematic UI audit | Passed; 150 Swift files, 54 presentation sites |
| Diff whitespace checks | Passed |

Both platform source phases include MediaReliabilityPolicy.swift. Twelve XCTest cases were added
and the iOS test bundle compiles; those cases have not been executed on a device/simulator.
Final review corrected automatic failover so it also honors requireCachedStreams, not only the
picker's separate cached-only toggle. Build numbers differ because each shared-scheme invocation
reserves a unique project number; code/marketing version is shared and no platform source drift
was introduced. Public MARKETING_VERSION was not changed.

No Worker/API/schema/vendor changes, external writes, commits, pushes, uploads or deployments.
No simulator was run. Existing third-party build warnings remain. No user library, download or
credential was deleted by the task.

## Acceptance still required

On physical iPhone/iPad/Apple TV, test cancellation/failover, paused/recovered downloads, network
loss and late-title resume, subtitle selection, prompts, largest text sizes, Reduce Motion,
VoiceOver and Siri Remote focus/back. Generic-device compilation and pure checks are not playback
or visual/device QA. The linked implementation reports define compatibility/fallback and the
complete fifty-item evidence; no production provider rollout is required before this client update.
