# Making Kodi addons compatible with FrameTV

FrameTV's addon system speaks the **Stremio addon protocol** (an HTTP
manifest that exposes `stream`, `subtitles`, `catalog`, and `meta`
resources as JSON). Kodi addons are **Python plugins** that run inside
Kodi's own runtime and are not directly loadable, because iOS and tvOS
cannot execute arbitrary Python and Apple does not allow shipping a
plugin interpreter. Compatibility therefore means bridging, not
importing. Here are the realistic ways to do it, from least to most
effort.

## 1. Prefer a Stremio-protocol equivalent (no bridge)
Many popular Kodi sources already have a Stremio addon counterpart that
exposes the same catalogs or streams over the manifest protocol. This is
the cleanest path: add the Stremio addon URL under Sources and it works
natively, on iPhone, iPad, and Apple TV, with no server to run. FrameTV
already consumes `stream` and `subtitles` resources from any such addon.

## 2. Run a local or self-hosted translation shim
Write a small web service that speaks the Stremio manifest on the
outside and calls the Kodi addon's logic on the inside:

- Host a lightweight server (Node, Python/Flask, or a Cloudflare Worker
  like the one already in this repo under `worker/`).
- Expose `/manifest.json` describing the resources you support.
- For `/stream/{type}/{id}.json`, translate the request, invoke the Kodi
  scraper logic (either reimplemented, or run headless via a Kodi
  instance / kodi-headless in Docker), and return Stremio-shaped JSON.
- Point FrameTV at that server's manifest URL.

This keeps all the "addon" work off-device and inside a service you
control, which is what Apple's guidelines expect.

## 3. Reuse the Kodi addon's scraper, reimplemented
Kodi addons are usually thin scrapers over public metadata plus a
resolver. You can port just the parts you need:

- Extract the source list and URL-resolving logic from the addon's
  Python.
- Reimplement it as endpoints in your shim (step 2) or, for resolving
  hosters, lean on Real-Debrid, which FrameTV already integrates.
- Return the resolved direct URL as a Stremio `stream` object.

## 4. Use a headless Kodi as a backend
For addons that are hard to reimplement, run **kodi-headless** on a
server, drive it through its JSON-RPC API, and wrap that behind a
Stremio manifest shim. FrameTV talks only to the shim. This is the most
faithful but the heaviest to operate.

## What FrameTV expects from a bridge
- A reachable HTTPS `manifest.json` listing `resources`
  (`stream`, `subtitles`, ...), `types` (`movie`, `series`), and
  `idPrefixes` (usually `tt` for IMDb ids).
- `stream` responses as `{ "streams": [ { "url": "...", "title": "..." },
  ... ] }`. Magnet or debrid-style results are resolved through the
  existing Real-Debrid path.
- `subtitles` responses as `{ "subtitles": [ { "url": "...", "lang":
  "en" }, ... ] }`, which merge automatically with OpenSubtitles.

## What will not work
- Dropping a Kodi `.zip` addon into the app: there is no Python runtime
  on device and Apple does not permit adding one.
- Addons that depend on Kodi-only APIs (the skin engine, the Kodi
  database, `xbmc.*` modules) unless that logic is reimplemented in a
  shim.

## Practical recommendation
Ship the Stremio-protocol path (step 1) as the default, and document the
shim approach (step 2) for power users. That covers the majority of what
people want from Kodi addons — catalogs, streams, and subtitles — while
staying within what iOS, iPadOS, and tvOS allow.
