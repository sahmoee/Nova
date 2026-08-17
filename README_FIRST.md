# Read me first

Also apply the ten additive README-first safeguards in `PROJECT_GUIDE_ADDITIONS.md`; they extend this project-specific contract without removing existing functionality.

Nova is a local-first iOS/iPadOS/tvOS personal-media app. User libraries and progress are authoritative; remote metadata, AI, tracking, and sharing are optional. Start in `Nova/App`, then the relevant `Nova/Services` or `Nova/Views` area. Keep credentials in Keychain, never source control.

Production AI/share calls use `https://api.sowensstudios.com/nova`. Verify both platform impact and the narrowest applicable tests/build.

AI is Apple-first for supported local work. Included cloud AI is only unlocked on Jessie's production/test devices with the local `Joo` gate; public installs use Apple Intelligence or a private UnifiedWorker. Private Workers may select Claude or OpenAI model IDs and keep provider keys in Worker secrets, never in the app.
