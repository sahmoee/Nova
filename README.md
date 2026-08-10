# Nova

Nova is a local-first personal media experience for iPhone, iPad, and Apple TV. It brings a user's own library and services into a fast, cinematic interface with universal search, watch progress, profiles, optional AI-assisted discovery, and private iCloud backup and restore.

Nova does not provide media or access to third-party content. Users are responsible for the sources and services they connect and for having permission to access their media.

## Highlights

- Native SwiftUI app for iOS, iPadOS, and tvOS
- Personal library, favorites, watch history, and continue watching
- SMB folders, Live TV playlists, direct media URLs, and user-installed add-ons
- Optional Trakt, TMDB, OMDb, OpenSubtitles, and Real-Debrid integrations
- Optional AI discovery through a user-controlled Cloudflare Worker
- Private iCloud configuration backup and file export (.nova snapshots)
- Apple player and VLCKit playback engines
- Dynamic Type, VoiceOver labels, adaptable layouts, and tvOS focus support

## Build

1. Open `Nova.xcodeproj` in the current Xcode release.
2. Select `Nova-iOS` or `Nova-tvOS`.
3. Set your development team and signing configuration.
4. Add service credentials in the app's Settings screen or use `NovaConfig.example.json` as a local template. Never commit real credentials.

Swift Package Manager resolves AMSMB2 3.4.0 and vlckit-spm 3.6.0. Network services are maintained separately in the [UnifiedWorker repository](https://github.com/sahmoee/UnifiedWorker); no backend secrets are stored here.

## App Store and support

- [App Store metadata](APP_STORE_METADATA.md)
- [Privacy policy](PRIVACY.md)
- [License](LICENSE.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)
- [Support](SUPPORT.md)
- [Public support site](https://sahmoee.github.io/Nova/)

## License

Nova's original source and assets are proprietary unless a file states otherwise. App Store distributions use Apple's Standard Licensed Application End User License Agreement. See [LICENSE.md](LICENSE.md) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
