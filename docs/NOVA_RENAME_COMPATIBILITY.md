# Nova rename compatibility

Nova is the product name. The following Astra identifiers are permanent storage
and App Store identities and must not be renamed:

- iOS app: `com.astra.app.ios`
- tvOS app: `com.astra.app.tvos`
- widget: `com.astra.app.ios.widgets`
- App Group: `group.astra.ios`
- Keychain service: `com.astra.app.secrets`

Keeping these values makes Nova an in-place Astra update and preserves the app
sandbox, iCloud key-value store, App Group, and Keychain. Creating new `com.nova`
App IDs would install a separate app and make Astra iCloud snapshots invisible.

## Backup compatibility

- Nova continues to read and write the production iCloud key
  `backup.snapshot.v1`.
- FrameTV schema v1 and Astra schema v2 decode through the compatibility layer.
- `.frametv`, `.astra`, `.nova`, and JSON snapshot files are accepted.
- Restored `frametv://` and `astra://` routes are normalized to `nova://`.
- Nova writes a small `backup.snapshot.writer` marker; it does not duplicate the
  snapshot, preserving the iCloud KVS quota.

## Apple Developer / App Store Connect checklist

1. Rename the existing Astra App Store listing to Nova; do not create a new app.
2. Keep the existing Astra App IDs and enable iCloud Key-Value Storage on the iOS
   and tvOS identifiers.
3. Keep `group.astra.ios` enabled on the app, widget, and Top Shelf profiles.
4. Regenerate development, ad-hoc, and distribution provisioning profiles after
   confirming those capabilities.
5. Test an upgrade from the last shipped Astra build on physical iPhone/iPad and
   Apple TV devices signed into the same iCloud account.

FrameTV's old iCloud KVS namespace (`com.frametv.app.ios` / `.tvos`) is a separate
container. Apple exposes one KVS container identifier per executable, so a single
Nova build cannot query both Astra and FrameTV KVS namespaces directly. FrameTV
snapshot files are supported; a cloud-only FrameTV snapshot needs to be exported
from FrameTV/Astra first or migrated by a separately signed bridge build.
