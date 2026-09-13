# iOS show detail crash

Reported behavior: Nova terminated when an iOS user selected a television show.

The title-detail body evaluates library membership immediately. That path created an internal
catalog placeholder by interpolating `ContentID.stableKey` into `URL(string:)` and force-unwrapping
the result. Series supplied by add-ons may use provider-controlled identifiers containing spaces,
URL delimiters, percent signs, or Unicode, so a malformed URL could trap before the detail screen
appeared. The same unsafe construction existed in `CatalogItem.asLibraryItem()`.

Both paths now use one `URLComponents`-based `catalogPlaceholderURL`. The content identity is stored
as a percent-encoded query value and URL creation has a non-optional local fallback. A regression
fixture covers a series identifier containing whitespace, delimiters, percent signs, brackets, and
Japanese text.

Validation: configuration, bundle-ID, registration, plist, QA-number, and diff guards passed. An
unsigned generic iOS `build-for-testing` compiled the app, widget, and test bundle without a
simulator. The originally affected title still needs to be selected on the reporting iPhone to
confirm the runtime symptom is gone; no matching device crash report was available through the
paired-device crash-log service.
