# Nova identifiers

Nova is the product name and the technical identity. These values must agree
across the app, widgets, tvOS target, entitlements, and the project configuration
(`NovaIdentifiers.swift` is the single source of truth; `validate_nova_config.sh`
enforces them in CI):

- iOS app: `com.nova.app.ios`
- tvOS app: `com.nova.app.tvos`
- widget: `com.nova.app.ios.widgets`
- tests: `com.nova.app.ios.tests`
- App Group: `group.nova.ios`
- Keychain service: `com.nova.app.secrets`
- Deep-link scheme: `nova://`
- Team ID: `5DV5N49VG8`

## Backup

- Nova reads and writes the iCloud key-value key `backup.snapshot.v1`, plus a
  small `backup.snapshot.writer` marker recording which app wrote it.
- Snapshot files use the `.nova` extension (plain `.json` is also accepted).
- A decoded snapshot with no writer marker and an early schema version is
  labelled generically as imported from "an earlier version".

## Apple Developer / App Store Connect checklist

1. Register the `com.nova.app.*` App IDs and enable iCloud Key-Value Storage on
   the iOS and tvOS identifiers.
2. Enable the `group.nova.ios` App Group on the app, widget, and tvOS profiles.
3. Add the `com.nova.app.secrets` Keychain sharing group.
4. Regenerate development, ad-hoc, and distribution provisioning profiles after
   confirming those capabilities.
