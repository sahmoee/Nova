# Nova Privacy Policy

**Effective date: August 8, 2026**

**Last updated: August 8, 2026**

Nova is a local-first personal media app for iPhone, iPad, and Apple TV. Nova has no advertising SDK, analytics SDK, or cross-app tracking. The developer does not operate a Nova user-account service and does not sell personal information.

This policy explains what the app stores, what may leave your device when you choose to use an integration, and the controls available to you.

## Information stored by Nova

Nova stores the following information on your device:

- Your library, favorites, watch history, playback progress, profiles, preferences, installed add-ons, and configured sources.
- Cached artwork, metadata, subtitles, and other data needed to display and play your media.
- Service credentials and tokens you enter. Sensitive credentials are stored in Apple Keychain where supported.

Nova can optionally synchronize settings and a backup snapshot through Apple's private iCloud key-value storage. This data is associated with your Apple ID and governed by Apple's terms and privacy policy. The Nova developer cannot access your private iCloud container.

## Services you choose to connect

Nova sends requests only when needed for features you use. Depending on your configuration, data may be sent directly from your device to:

- **TMDB and OMDb:** search terms, title identifiers, and related metadata requests.
- **Trakt:** account authorization, lists, watch history, and playback progress you choose to synchronize.
- **Real-Debrid:** the account token and links needed to use your account.
- **OpenSubtitles:** title or file-identification information needed to find subtitles.
- **SMB servers and Live TV providers:** credentials and requests needed to browse or play sources you add.
- **Add-ons:** catalog, title, and playback requests defined by add-on URLs you install.

Those providers process data under their own terms and privacy policies. Nova does not control them. You should review a provider's policy before connecting it.

## Optional AI features

AI features are off until you configure a compatible Cloudflare Worker. When used, the text you submit and the limited context needed to answer it may be sent to your Worker and then to its configured AI provider, currently Anthropic. Library-assisted requests may include media titles from your library. Nova does not send passwords or account tokens to the AI provider.

The person who deploys the Worker controls its Cloudflare account, configuration, logs, retention, and AI-provider account. The included Worker does not create a prompt-history database, but Cloudflare observability or the AI provider may process request data under their respective policies. Remove the Worker URL and token in Settings to stop using AI features.

## Backup files and share codes

You can create backups that include settings, sources, add-ons, and—only when you explicitly select them—credentials. Exported backup files remain wherever you save or share them.

If you create a share code, the selected snapshot is stored in the Cloudflare Worker you configured. Codes expire after the selected period (7 days by default and no more than 30 days) and are deleted when redeemed or when the expiration alarm runs. A backup that includes credentials is sensitive; share it only with someone you trust.

## Data the developer collects

The Nova app does not send analytics, advertising identifiers, contacts, photos, precise location, or viewing activity to the developer. The developer may receive information you voluntarily send in a support email, such as your email address and message. Support correspondence is used only to respond, diagnose issues, prevent abuse, and meet legal obligations, and is retained only as long as reasonably necessary for those purposes.

Apple and the App Store may independently process purchase, diagnostic, or device information under Apple's privacy policy. Service providers you configure process data independently as described above.

## Your choices and deletion

You can:

- Disconnect Trakt or Real-Debrid and remove other service credentials in Settings.
- Remove add-ons, sources, the AI Worker URL, and locally stored library items.
- delete Nova's on-device data by deleting the app;
- manage Nova's iCloud data through your Apple ID/iCloud settings; and
- request deletion of support correspondence by emailing the address below, subject to information that must be retained for legal or security reasons.

Nova has no central account to delete. Deleting Nova does not delete data held by an external service; use that provider's account controls for those requests.

## Children

Nova is a general-audience personal media app and is not directed to children under 13. The developer does not knowingly collect personal information from children. If you believe a child submitted personal information through support, contact us so it can be deleted.

## Security

Nova uses platform protections such as Apple Keychain and encrypted HTTPS connections where providers support them. No method of storage or transmission is completely secure. Protect exported backups and do not install add-ons or connect services you do not trust.

## Changes to this policy

This policy may change as Nova evolves. The effective date will be updated when changes are published. Material changes will be described in the app or on the public support site when appropriate.

## Contact

For privacy questions or requests, email [sowensstudios@yahoo.com](mailto:sowensstudios@yahoo.com).

Public policy URL: <https://sahmoee.github.io/Nova/privacy.html>
