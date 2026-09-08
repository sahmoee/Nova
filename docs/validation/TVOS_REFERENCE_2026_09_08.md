# tvOS reference redesign validation — September 8, 2026

Scope: Nova's Apple TV Home, floating navigation, Library, settings panels, and the shared persistence used by manual settings transfer and scoped resets. iPhone/iPad retain their existing layout; the visible library name is Library on all platforms.

## Implemented

- Back-accessible upper-left Remote / Home / Search / Library / Settings menu. Pushed screens retain native Back navigation. Visited sections retain their state and inactive sections cannot receive focus.
- Artwork-led Home with real title logos and a text fallback, metadata, Play/Resume, queue, information, next-title controls, page indicators, and landscape Continue Watching cards. Rotation stops outside the active Home screen and respects reduced motion and VoiceOver.
- Six-column 2:3 Library posters, title labels, cached-metadata genres, media types, stable sorting, and actual filtered counts. Existing library management functions remain in Options.
- Horizontal settings categories, shared white focus highlights, and adjustable focus glow. Manual iCloud Push/Pull, local counts and mirror availability, bounded URL snapshot preview/import, and separately confirmed history/addon/preference/library resets.
- Additive deletion markers and backup acknowledgements prevent updated clients from adopting older deleted data. Device-only resets pause the affected category; History also pauses the composite Library mirror. Explicit Push/Pull resumes it. Older clients cannot be forced to honor the new markers.

## Passed

| Check | Result |
| --- | --- |
| Apple TV simulator Debug build | Nova 1.7 (93), tvOS 27.0 SDK/runtime |
| Signed generic Apple TV Debug build | Nova 1.7 (94) |
| Signed generic iPhone/iPad Debug build | Nova 1.7 (95), including widget |
| New settings/backup/URL policy fixtures | 9 native assertion fixtures |
| Title-logo selection fixtures | 4 native assertion fixtures |
| QA build-number fixtures | 7 checks |
| Cinematic UI source audit | 153 files, 56 presentation sites |
| Source registration | All Swift sources registered for both app targets |
| Project plist and whitespace | Passed |
| Public Nova feature-page source review | Updated locally; product-sync check passed |

The policy fixtures execute production declarations in a native harness; they are not an account-backed multi-device iCloud test. Marketing version remains 1.7. Automatic shared-scheme build numbers were used.

## Pending

- Visual comparison against the five supplied photos and live remote Back/focus verification. The user approved simulator use for this pass. The tvOS simulator was created and Nova installed/launched, but Device Hub interaction was blocked by the Mac's locked session. An unlock was requested.
- Physical Apple TV installation/playback. No paired Apple TV was available through the local device inventory.
- Account-backed cross-device iCloud delivery and deletion. No personal library, history, preferences, addons, or shared backups were deleted during this work.

Do not claim pixel-for-pixel verification, successful remote testing, or confirmed cloud delivery from a build alone. MDBList and Trakt panels route existing addon/import features; Web Management imports private snapshots and is not a new web server.
