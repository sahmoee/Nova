# Nova gray / black pastel styling

September 24, 2026. Requested by the user as the Nova adaptation of Stocked's softer styling.

## Restore and ownership

Restore tag `restore/nova-pre-pastel-2026-09-24` points to `dda3846`, the clean pre-change checkout.
Nova owns these presentation-only changes. Theme and AccentManager produce the shared tokens;
iPhone/iPad/tvOS views and iOS/tvOS/widget accent assets consume them. No stored settings, libraries,
playback, credentials, provider schemas, backend, or website contracts change. The Watch already uses
neutral tint; its native controls remain the companion presentation. Rollback is a code revert.

## Design

- Charcoal canvas (7.5% gray), elevated background (11.5%), graphite cards (16%), raised cards (21%).
- Pearl-gray accent (84%) with dark filled-button labels (10%). Secondary accent is 72% gray.
- Rounded shared cards, posters, grouped settings, navigation items, and buttons.
- Serif screen, hero and section headings; readable system body and control text.
- Matte grouped surfaces, fine borders and diffuse shadows. Existing media artwork supplies imagery.
- Home, Search, Library and Settings retain their navigation and real content. Title details, sheets,
  source controls and subsidiary destinations inherit the same theme through shared components.
- tvOS retains its Back menu, six-column Library and native focus behavior, including dark labels
  on the bright focused surface. Warning/error/success colors continue to communicate state.

This request supersedes the earlier blue iOS accent and system display-heading rule. It does not
require generated movie artwork, change title/provider branding, or introduce image-based chrome.

## Verification

Release Xcode 27.0 (27A266a) generic iOS/iPadOS build 250 and tvOS build 251 passed.
The iOS app, widget and embedded Watch all carry build 250. Strict deep signing verification
passed for both apps. Dependency Makefile warnings were nonfatal; the iOS build also emitted
Xcode's diagnostic “command failed with exit code 0” while the overall build returned success.

Four palette text contrast pairs passed: pearl/onAccent 12.06:1, pearl/canvas 12.80:1,
pearl/card 10.06:1 and secondary pearl/raised card 6.11:1. Surface tone ordering passed.
These checks do not establish poster-overlay contrast for every piece of media artwork.

No simulator or physical screen pass was performed. Device visual acceptance, Dynamic Type,
iPad resizing and Apple TV remote focus remain pending. No data/provider/backend tests were
needed for this presentation-only batch. The iPhone install stalled despite a connected device listing; a separate read-only app query timed out after 15 seconds. The stalled installer was interrupted, and installation remains unconfirmed pending an unlocked device.

After the user unlocked the iPhone, the bounded retry successfully installed Nova iOS build 250.
