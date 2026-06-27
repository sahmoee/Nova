# App Store Review Notes — FrameTV

## Summary for App Review

This app is a personal media player for content the user owns, controls, or is authorized to
access. It does not include a content catalog, torrent search engine, scraper, piracy index, DRM
bypassing, or unauthorized media source list. Users manually configure their own SMB shares, direct
URLs, and Real-Debrid account. Magnet links require an explicit confirmation that the user has legal
access to the content.

## Additional context for the reviewer

- **No bundled content and no discovery.** FrameTV ships with nothing to watch except a handful of
  well-known public-domain / Creative-Commons sample videos (the Blender open-movie shorts) used to
  demonstrate the interface. There is no in-app search, no catalog, no recommendations of where to
  find media, and no list of sources.

- **User-supplied sources only.** Everything playable is something the user explicitly adds:
  - an SMB share on their own network,
  - a direct URL to a file they paste in,
  - a link resolved through the user's own Real-Debrid account,
  - or a Stremio-protocol addon the user installs by pasting its manifest URL.

- **Addons are user-supplied; none are bundled or suggested.** FrameTV does not ship with any addons,
  does not host an addon catalog, and does not recommend specific addons or where to obtain them.
  The "AIOStreams" and "Comet" quick-add entries are blank prefilled forms that require the user to
  paste their own self-hosted/configured instance URL; FrameTV has no default endpoints for them. An
  addon must be added by the user before any stream lookup can occur.

- **Metadata is descriptive only.** The optional TMDB integration (using the user's own API key)
  provides titles, posters, descriptions, and season/episode listings for display. It is not a media
  source and does not provide or link to playable files. Trakt integration (user's own account) only
  syncs the user's watchlist and watched progress. OpenSubtitles integration (user's own key) only
  retrieves subtitle text. None of these provide media content.

- **Torrent handling.** When an installed addon returns a torrent stream, FrameTV resolves it solely
  through the user's own Real-Debrid account (a service the user separately subscribes to). FrameTV does
  not download, seed, or share torrent data itself, and includes no BitTorrent client.

- **Legal-access gating.** Before submitting a magnet link or an unverified direct link, the user
  must check a confirmation that reads: "I confirm I own, control, or am authorized to access this
  content." This gate can be reviewed in Settings ▸ Privacy & Legal Info.

- **No DRM circumvention.** FrameTV plays standard, unprotected video files through Apple's AVPlayer. It
  does not decrypt, strip, or work around any protection.

- **Privacy.** FrameTV has no analytics and no servers of its own. Credentials (Real-Debrid token, SMB
  passwords) are stored only in the system Keychain and are never transmitted anywhere except to the
  service the user configured them for.

## How to exercise the app during review

1. Launch the **FrameTV-tvOS** scheme on an Apple TV simulator. The Home screen shows the seeded
   public-domain samples.
2. Open any sample and press Play to verify standard AVPlayer playback, then exit and re-open to see
   resume behavior.
3. Open **Sources ▸ Direct URL**, paste a direct link to a video file you control, confirm legal
   access if prompted, and choose **Add & Play** to see the full add-and-play path.
