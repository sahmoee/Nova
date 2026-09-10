# tvOS action and platform-boundary audit — September 9, 2026

Scope: Nova Home, root navigation, Settings, media-source management, player entry points, remote focus, and iOS/tvOS compile boundaries.

## Result

- Home now follows one television hierarchy: featured artwork and primary playback actions, Continue Watching, then a bounded set of personalized/editorial shelves.
- Removed Home setup status, source-health cards, shortcut destinations, the duplicate queue-management card, the manual next-feature button, and bottom customization/profile buttons on tvOS. Their real destinations remain available through Settings, Library, detail context menus, or the root menu.
- Replaced fifteen simultaneous Settings categories and a competing detail scroll view with five native NavigationLink destinations: Playback, Sources, Library, Experience, and Data & Privacy.
- Each Settings destination owns one vertical ScrollView and focus section. Native NavigationStack, NavigationLink, Toggle, and Back behavior now control interaction.
- Removed obsolete tvOS controls for the old Quick Access, source-health, and Smart Collections Home sections; remaining Home controls now correspond to visible television behavior.
- Consolidated real media functions under Sources: Jellyfin/Plex/Emby servers, SMB shares, Live TV, Real-Debrid, add-ons, and supported account tracking.
- Kept provider claims accurate: Nova does not expose a fake MDBList login, connected Trakt provider, or Apple TV-hosted web server.
- Kept Play/Resume, add/remove Up Next, More Info, progress, Start Over, remove-from-Continue-Watching, stream selection, subtitles, and source maintenance.

## Platform boundaries

| Area | tvOS behavior | iOS behavior |
| --- | --- | --- |
| Navigation | Floating Back menu plus native pushed destinations | Bottom home bar / iPad sidebar |
| Settings | Five-category remote directory | Searchable grouped Settings directory |
| Home gestures | Focus and clickpad navigation | Drag hero paging and pull-to-refresh |
| Player launch | Built-in Apple/VLC tvOS paths | Built-in plus iOS external-player URL paths |
| Feedback | Focus/remote feedback | UIKit haptics |
| Editing | Remote-safe actions and menus | EditButton, touch reordering, and share sheets where supported |
| Presentation | tvOS full-screen/pushed flows | iOS detents, drag indicators, and touch sheets where supported |

Touch-only APIs remain guarded by iOS conditional compilation or live in iOS-only declarations. The full tvOS target compiling both simulator and physical-device SDK variants is the compile-time boundary check.

## Verification

| Check | Result |
| --- | --- |
| Generic tvOS Simulator Debug build | Passed |
| Generic physical tvOS Debug build (arm64 device SDK) | Passed |
| Generic iOS Simulator Debug build, including widget | Passed |
| Cinematic UI source audit | Passed: 156 files, 58 presentation sites |
| Native presentation policy checks | Passed: 17 |
| QA build-number tests | Passed: 7 |
| Whitespace and patch validation | Passed |

The paired “Living Room” Apple TV was registered but unreachable during this audit, so physical Siri Remote traversal remains a device acceptance check. On the device, verify: Settings focus moves down through all five categories; Select pushes each destination; every destination scrolls to its final control; Back returns to the directory; Back at the directory opens Nova's menu; Home focus moves from Play across queue/info and down to Continue Watching without oversized overlap.
