# Nova UI and UX redesign — 2026-09-09

This pass removes AI as a primary destination and treats it as a search capability. The shared shell now has four stable destinations: Home, Search, Library, and Settings. Existing `nova://ai` links remain compatible and open Search.

## 15 UI improvements

1. Replaced the five-item iPhone tab strip with a four-item floating home bar.
2. Removed “Ask Nova” from persistent navigation.
3. Uses a restrained material surface that follows Reduce Transparency.
4. Uses system blue only for the selected iOS destination.
5. Gives every home-bar destination equal width and a 49-point minimum target.
6. Uses one-line compact labels to preserve content height.
7. Keeps the Now Playing card immediately above navigation.
8. Keeps inactive iPhone roots mounted without leaving them visible.
9. Redesigned the tvOS menu with a clear Nova heading and current-section context.
10. Separates Remote Help from navigation destinations.
11. Strengthened the tvOS menu backdrop so underlying content does not compete with focus.
12. Replaced the crowded tvOS Settings strip and competing detail pane with five native push-navigation categories.
13. Added category symbols, concise descriptions, and independently scrolling category screens to tvOS Settings.
14. Simplified the iOS Settings header to a compact native hierarchy.
15. Replaced decorative Discover tiles with live library, collection, history, and channel artwork.

## 15 UX improvements

1. Reduced top-level choices from five to four.
2. Integrated assisted discovery into Search as “Smart Search.”
3. Preserved old AI deep links by routing them to Search.
4. Corrected New & Hot deep links so they no longer open the former AI tab.
5. Re-selecting a destination still returns its navigation stack to its root.
6. Each iPhone destination retains its navigation and scroll state after switching.
7. Inactive roots are disabled, ignore touches, and are hidden from accessibility.
8. Home-bar items announce their selected state.
9. Home-bar items explain whether they open or reset a destination.
10. tvOS menu items announce selection and their result.
11. Remote Help identifies itself as help instead of appearing as a destination.
12. tvOS Settings has only one active vertical focus/scroll region at a time.
13. tvOS Settings enters a category with native NavigationLink/Back behavior instead of swapping a neighboring panel.
14. Accessibility remains directly reachable inside the Experience category.
15. Settings search matches titles, details, and stable category identifiers.

## Constraints changed

- `AppTab.ai` remains only as a compatibility route. New chrome must use `AppTab.primaryTabs`.
- New assisted-discovery entry points belong in Search and use the name “Smart Search.”
- iPhone navigation uses `NovaHomeBar`; the legacy `TabView` implementation should not receive new destinations.
- tvOS Settings uses a short native directory. New settings belong in one of the five existing destinations unless a genuinely new top-level responsibility justifies expanding it.
- Navigation and focus containers must hide inactive content from accessibility as well as hit testing.
