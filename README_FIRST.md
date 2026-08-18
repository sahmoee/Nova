# Read me first

Also apply the ten additive README-first safeguards in `PROJECT_GUIDE_ADDITIONS.md`; they extend this project-specific contract without removing existing functionality.

Nova is a local-first iOS/iPadOS/tvOS personal-media app. User libraries and progress are authoritative; remote metadata, AI, tracking, and sharing are optional. Start in `Nova/App`, then the relevant `Nova/Services` or `Nova/Views` area. Keep credentials in Keychain, never source control.

Production AI/share calls use `https://api.sowensstudios.com/nova`. Verify both platform impact and the narrowest applicable tests/build.

SMB connections prefer Tailscale MagicDNS names (`*.ts.net`) over numeric addresses. Existing Tailscale IP shares upgrade in place when reverse DNS is available, preserving share IDs and Keychain credentials; IP and LAN names remain offline-compatible fallbacks. A personal default may be supplied only through machine-local `NovaConfig.json` as `preferredSMBServer` and must not be committed.
