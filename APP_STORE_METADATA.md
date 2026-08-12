# Nova App Store Metadata

Prepared August 8, 2026. Review every field against the production build before submission.

## Core listing

**Name (4/30):** Nova

**Subtitle (28/30):** Your Personal Media Universe

**Promotional text (156/170):** Your library, beautifully unified. Search, organize, and resume your personal movies and shows across iPhone, iPad, and Apple TV—with optional AI discovery.

**Keywords (92/100 bytes):** media,player,movies,shows,library,streaming,SMB,playlist,watchlist,metadata,subtitles,TV

**Primary category:** Entertainment

**Secondary category:** Photo & Video

## Description

Your media, beautifully unified.

Nova is a cinematic home for the movies and shows you own, control, or are authorized to access. Bring your personal library and compatible services together, find what you want quickly, and continue watching across iPhone, iPad, and Apple TV.

YOUR LIBRARY, YOUR WAY
Organize personal movies and series from sources you choose. Rich artwork, episode information, favorites, watchlists, and viewing progress keep everything easy to browse.

BUILT FOR THE BIG SCREEN
Nova feels at home on Apple TV with a focus-friendly interface, bold artwork, quick navigation, and playback controls designed for the remote. Adaptive layouts provide the same polished experience on iPhone and iPad.

SEARCH AND DISCOVER
Search your connected catalog in one place. Optional AI-assisted discovery can turn natural-language ideas into personalized shelves when you connect your own compatible Worker.

PICK UP WHERE YOU LEFT OFF
Continue watching, track completed titles, and return to recently played media without hunting for your place.

FLEXIBLE PLAYBACK
Use Apple's native player for system integration or the included alternate engine for broad format support. Choose audio, subtitles, playback speed, and appearance controls supported by your media.

PRIVATE BY DESIGN
Nova is local-first, includes no advertising or cross-app tracking, and has no Nova account to create. Credentials are stored using Apple Keychain where supported. Optional private iCloud backup helps move your setup between your Apple devices.

CONNECTED ON YOUR TERMS
Connect only the services and sources you choose. Every optional integration can be disconnected from Settings.

Nova does not include, sell, or provide media, subscriptions, or access credentials. You are responsible for ensuring you have permission to access every source and title you add. Features that rely on external services require your own account, API key, compatible server, or subscription and are subject to those providers' availability and terms.

## URLs

- **Support URL:** <https://sahmoee.github.io/Nova/support.html>
- **Marketing URL:** <https://sahmoee.github.io/Nova/>
- **Privacy Policy URL:** <https://sahmoee.github.io/Nova/privacy.html>
- **License URL:** <https://sahmoee.github.io/Nova/license.html>

## App privacy recommendation

The current code contains no ad or analytics SDK and its privacy manifest declares no tracking and no data collected by the developer. The likely App Store Connect selection is **Data Not Collected** by the developer.

Before submission, re-audit the archived production build, every enabled third-party SDK, support workflow, and any developer-operated Worker. Apple requires disclosures to include data collected by third-party partners. User-directed transfers to services they independently configure should be described in the public privacy policy even when the developer cannot access that data.

## tvOS privacy policy text

Nova is a local-first personal media app with no advertising or cross-app tracking. Library data, preferences, and service credentials are stored on the device; sensitive credentials use Apple Keychain where supported. Optional backup data is stored in the user's private iCloud container. When a user enables an integration, Nova sends only the requests needed to the provider they selected, such as TMDB, Trakt, OMDb, OpenSubtitles, Real-Debrid, an SMB server, an add-on, or the user's own AI Worker. These providers process data under their own terms. AI features are off until configured and may send entered text and relevant media titles to the user's Worker and its AI provider. The Nova developer does not receive viewing activity or operate a Nova account service. Users can disconnect services and remove credentials in Settings, delete on-device data by deleting the app, and manage iCloud data through Apple settings. Privacy requests: support@sowensstudios.com. Full policy: https://sahmoee.github.io/Nova/privacy.html

## App Review notes

Nova is a personal media player and organizer. It does not ship with media, a developer-hosted catalog, subscriptions, credentials, or a source-discovery service. Reviewers can use locally imported sample media or a direct HTTPS media URL they are authorized to access. Features requiring external accounts are optional and clearly identified in Settings. Review-Safe Mode in **Settings → Privacy & Legal** hides advanced third-party source features without changing the core library and playback experience.

Provide App Review with any temporary test credentials and exact navigation steps in App Store Connect; never place credentials in this repository.
