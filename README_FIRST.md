# Read me first

Also apply the ten additive README-first safeguards in `PROJECT_GUIDE_ADDITIONS.md`; they extend this project-specific contract without removing existing functionality.

Nova is a local-first iOS/iPadOS/tvOS personal-media app. User libraries and progress are authoritative; remote metadata, AI, tracking, and sharing are optional. Start in `Nova/App`, then the relevant `Nova/Services` or `Nova/Views` area. Keep credentials in Keychain, never source control.

Production AI/share calls use `https://api.sowensstudios.com/nova`. Verify both platform impact and the narrowest applicable tests/build.

Nova's existing managed AI service remains the default. AI Search may use a separate private Worker, Keychain-stored access token, and model ID; provider API keys belong only in that Worker's encrypted secrets. Never reuse another app's token or silently replace a saved Nova configuration.
