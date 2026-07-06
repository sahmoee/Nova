# Astra AI Worker

A small Cloudflare Worker that sits between the Astra app and the Anthropic API. The
app never holds your Anthropic key — this Worker does. The app calls the Worker; the
Worker calls Claude and returns clean JSON.

This replaces / updates whatever Worker you had before. The original behavior (the app
POSTs `{ "query": "..." }` to the root URL and gets `{ "titles": [...] }`) is preserved,
so nothing in the app breaks. New endpoints add the stream-filter assistant and the
troubleshooting helper.

---

## What you need (the short version)

1. A **Cloudflare account** (free tier is fine).
2. An **Anthropic API key** (from console.anthropic.com).
3. **Node.js** installed locally (to run `wrangler`, Cloudflare's deploy tool).

That's it. No database, no storage buckets, no extra services.

---

## Setup, step by step

From inside this folder:

```bash
# 1. Install the Cloudflare CLI (one time)
npm install -g wrangler        # or use: npx wrangler ... for each command

# 2. Log in to Cloudflare (opens a browser)
wrangler login

# 3. Store your Anthropic API key as a secret (you'll be prompted to paste it)
wrangler secret put ANTHROPIC_API_KEY

# 4. (Optional but recommended) lock the Worker to your app with a shared token
wrangler secret put FRAMETV_SHARED_TOKEN
#    -> paste any long random string. Leave this step out for now unless/until
#       the app sends the matching Authorization header (see "Securing it" below).

# 5. Deploy
wrangler deploy
```

After deploy, Wrangler prints your Worker URL, e.g.:

```
https://frametv-ai-worker.<your-subdomain>.workers.dev
```

**Put that URL into the app:** Settings → AI Search → Worker URL. That single URL powers
the AI tab (shelves, playlists, library search) and, as those features ship, the stream
filter and troubleshooting helpers.

### Test it before opening the app

```bash
# Health check (no AI call, no key needed beyond deploy):
curl https://frametv-ai-worker.<your-subdomain>.workers.dev/health
# -> {"ok":true,"model":"claude-sonnet-4-6"}

# Title generation (the main flow the app uses today):
curl -X POST https://frametv-ai-worker.<your-subdomain>.workers.dev/ \
  -H "Content-Type: application/json" \
  -d '{"query":"dark sci-fi thrillers"}'
# -> {"titles":["Blade Runner 2049","Ex Machina", ...]}
```

If `/health` works but `/` returns an error about `ANTHROPIC_API_KEY`, re-run step 3.

---

## Capabilities (every endpoint, what it does, what the app sends and gets)

All endpoints are `POST` and take/return JSON unless noted. The Worker accepts the
request at its root URL; the path selects the capability.

### 1. `POST /`  and  `POST /titles` — Title generation
**Used by:** AI tab Discover mode (AI-built shelves + playlist builder), and the app's
existing AI search.
**Send:** `{ "query": "a 5-movie friday night lineup" }`
**Get:** `{ "titles": ["Title 1", "Title 2", ...] }`
**Notes:** Returns real, TMDB-findable titles only (no years, no extra words). Honors an
explicit count in the prompt ("5 movies" → 5 titles); otherwise returns 12–20. The app
resolves each title through TMDB to get posters and details.
**Why `/` and `/titles` both exist:** `/` is the original contract the app already uses;
`/titles` is the same thing with an explicit name, so you can point future calls at it.

### 2. `POST /filter` — Stream filter assistant
**Used by:** (planned) the AI stream-filter assistant — "only show cached 1080p streams
under 8GB with English audio."
**Send:** `{ "query": "cached 1080p under 8GB english h265" }`
**Get:** `{ "filter": { "minQuality": "1080p", "maxSizeGB": 8, "cachedOnly": true,
"language": "EN", "codecPreferred": true, "hdrOnly": false } }`
**Notes:** The object's keys match the app's `ParsedStreamFilter`. Keys are omitted when
not implied. The app already has an on-device parser for simple phrases; this endpoint is
the smarter version for complex ones.

### 3. `POST /troubleshoot` — Playback troubleshooting helper
**Used by:** (planned) the AI troubleshooting helper shown when playback fails.
**Send:** `{ "error": "VLC: unsupported codec", "context": { "engine": "vlc",
"source": "addon", "container": "MKV", "host": "..." } }` (context optional)
**Get:** `{ "cause": "plain explanation", "advice": "one concrete next step",
"suggestedAction": "tryOtherEngine" }`
**`suggestedAction` is one of:** `tryOtherEngine`, `chooseDifferentStream`, `checkSMB`,
`checkAddons`, `none` — so the app can wire the advice to a real button.

### 4. `GET /health` — Deploy check
**Send:** nothing (GET).
**Get:** `{ "ok": true, "model": "claude-sonnet-4-6" }`
**Notes:** Does not call the Anthropic API, so it's a safe way to confirm the Worker is
up before spending any credits.

---

## Secrets and variables (what to set, and what each is)

Set with `wrangler secret put <NAME>` (secrets) — never put these in `wrangler.toml`.

| Name | Type | Required | What it is |
|---|---|---|---|
| `ANTHROPIC_API_KEY` | secret | **Yes** | Your Anthropic API key. The Worker sends it to the Anthropic API as `x-api-key`. The app never sees it. |
| `FRAMETV_SHARED_TOKEN` | secret | No | If set, every request must include `Authorization: Bearer <token>`. Stops strangers who find your Worker URL from spending your credits. Leave unset until the app sends this header. |
| `MODEL` | var (in `wrangler.toml`) | No | Which Claude model to use. Defaults to `claude-sonnet-4-6`. |

There is **no signing key, certificate, or app-side secret** to manage for the Worker
itself. "Signing" in the Apple sense (code-signing the app) is separate and handled in
Xcode with your Developer Team ID — it has nothing to do with this Worker.

---

## Securing it (optional, recommended once stable)

A Worker URL is effectively public — anyone who has it can POST to it and spend your
Anthropic credits. Two ways to reduce that risk:

1. **Shared token (built in):** set `FRAMETV_SHARED_TOKEN`, then have the app send
   `Authorization: Bearer <same token>`. Until the app sends that header, leave the
   secret unset (otherwise every request returns 401).
2. **Keep the URL private:** since you configure the URL in the app yourself and it isn't
   published anywhere, simply not sharing it is a reasonable baseline.

You can also add rate limiting in the Cloudflare dashboard (Security → WAF → Rate
limiting rules) to cap requests per minute.

---

## Cost

You pay Anthropic per token for the calls the Worker makes (title lists and filters are
small — a few hundred tokens each). Cloudflare Workers' free tier covers a generous number
of requests per day. Setting a spend limit in the Anthropic console is wise.

---

## Updating later

Edit `worker.js`, then `wrangler deploy` again. The URL stays the same, so you don't need
to change anything in the app.
