# Read me first

Also apply the ten additive README-first safeguards in `PROJECT_GUIDE_ADDITIONS.md`; they extend this project-specific contract without removing existing functionality.

Nova is a local-first iOS/iPadOS/tvOS personal-media app. User libraries and progress are authoritative; remote metadata, AI, tracking, and sharing are optional. Start in `Nova/App`, then the relevant `Nova/Services` or `Nova/Views` area. Keep credentials in Keychain, never source control.

Production AI/share calls use `https://api.sowensstudios.com/nova`. Verify both platform impact and the narrowest applicable tests/build.

SMB connections prefer Tailscale MagicDNS names (`*.ts.net`) over numeric addresses. Existing Tailscale IP shares upgrade in place when reverse DNS is available, preserving share IDs and Keychain credentials; IP and LAN names remain offline-compatible fallbacks. A personal default may be supplied only through machine-local `NovaConfig.json` as `preferredSMBServer` and must not be committed.

Trakt custom-list imports accept owned slugs and public trakt.tv list URLs. Imports remain local-first and may independently target Nova Tracker, the connected Trakt watchlist, Nova Library, and a deduplicated Nova collection; TMDB artwork enrichment is optional.
## Nova Tracker service

Nova Tracker is first-party and zero-configuration at `https://api.sowensstudios.com/tracker`.
Settings → Accounts → Nova Tracker exposes synced stats, recent activity, custom lists,
and portable JSON backup. Title detail pages can add a title to any custom list.
