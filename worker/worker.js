/**
 * FrameTV AI Worker
 * -----------------
 * A small Cloudflare Worker that sits between the FrameTV app and the Anthropic API.
 * The app never holds your Anthropic API key; this Worker does, in an environment
 * secret. The app talks to this Worker; the Worker talks to Claude.
 *
 * IMPORTANT — the app's current built-in contract:
 *   The app POSTs { "query": "<text>" } to the Worker's ROOT URL and expects
 *   { "titles": [ "Title 1", "Title 2", ... ] } back. That exact behavior is kept
 *   here (POST "/" and POST "/titles" both do it), so the existing Discover, shelf,
 *   playlist, and library-search features keep working with no app change.
 *
 * Additional endpoints below (/filter, /troubleshoot) power the AI stream-filter
 * assistant and the AI troubleshooting helper. They are additive — the app can adopt
 * them when those features ship; they don't affect the title flow.
 *
 * ENDPOINTS
 *   POST  /            -> title list      (back-compat: same as /titles)
 *   POST  /titles      -> title list      ({query} -> {titles:[...]})
 *   POST  /filter      -> stream filter   ({query} -> {filter:{...}})
 *   POST  /troubleshoot-> playback help   ({error, context} -> {cause, advice, suggestedAction})
 *   GET   /health      -> { ok: true }    (no AI call; for testing the deploy)
 *
 * SECURITY
 *   - ANTHROPIC_API_KEY is read from the environment (a Wrangler secret). Never hard-code it.
 *   - Optional FRAMETV_SHARED_TOKEN: if set, requests must send header
 *       Authorization: Bearer <token>
 *     This stops strangers who find your Worker URL from spending your API credits.
 *     (The app does not send this header yet; leave FRAMETV_SHARED_TOKEN unset for now,
 *      or add the header in the app before enabling it.)
 *
 * MODEL
 *   Uses claude-sonnet-4-6 by default. Override with the MODEL environment variable.
 */

const DEFAULT_MODEL = "claude-sonnet-4-6";
const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, "") || "/";

    // CORS preflight (harmless for a native app; useful if you ever call from a browser).
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }

    if (request.method === "GET" && path === "/health") {
      return json({ ok: true, model: env.MODEL || DEFAULT_MODEL });
    }

    if (request.method !== "POST") {
      return json({ error: "Method not allowed" }, 405);
    }

    // Optional shared-token gate.
    if (env.FRAMETV_SHARED_TOKEN) {
      const auth = request.headers.get("Authorization") || "";
      const token = auth.replace(/^Bearer\s+/i, "");
      if (token !== env.FRAMETV_SHARED_TOKEN) {
        return json({ error: "Unauthorized" }, 401);
      }
    }

    if (!env.ANTHROPIC_API_KEY) {
      return json({ error: "Worker is missing ANTHROPIC_API_KEY" }, 500);
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return json({ error: "Invalid JSON body" }, 400);
    }

    try {
      switch (path) {
        case "/":
        case "/titles":
          return await handleTitles(body, env);
        case "/filter":
          return await handleFilter(body, env);
        case "/troubleshoot":
          return await handleTroubleshoot(body, env);
        default:
          return json({ error: "Not found" }, 404);
      }
    } catch (err) {
      return json({ error: "Worker error", detail: String(err) }, 502);
    }
  },
};

/* ----------------------------------------------------------------------------
 * /titles  — natural language -> list of real movie/show titles
 *   Request:  { "query": "dark sci-fi thrillers" }
 *   Response: { "titles": ["Blade Runner 2049", "Ex Machina", ...] }
 * The app resolves each title through TMDB, so we only need clean, real titles.
 * -------------------------------------------------------------------------- */
async function handleTitles(body, env) {
  const query = (body.query || "").toString().trim();
  if (!query) return json({ error: "Missing query" }, 400);

  const system =
    "You are a film and TV recommendation engine for a media app. " +
    "Given a user's request, reply with a list of real, existing movie or TV show titles " +
    "that best match it. Rules: " +
    "1) Output ONLY a JSON array of strings, nothing else — no prose, no markdown, no keys. " +
    "2) Each string is a single real title as it appears on TMDB (no year, no extra words). " +
    "3) If the user asks for a specific count (e.g. '5 movies'), return that many. " +
    "Otherwise return 12 to 20. " +
    "4) Prefer well-known, findable titles. Do not invent titles. " +
    "5) No duplicates.";

  const content = await callClaude(env, system, query, 1024);
  const titles = extractStringArray(content);
  return json({ titles });
}

/* ----------------------------------------------------------------------------
 * /filter — natural language -> structured stream filter
 *   Request:  { "query": "cached 1080p under 8GB with english audio" }
 *   Response: { "filter": { minQuality, maxSizeGB, cachedOnly, language,
 *                           codecPreferred, hdrOnly } }
 * Shape matches the app's ParsedStreamFilter. The app already has an on-device
 * parser; this endpoint is the smarter cloud version for complex phrases.
 * -------------------------------------------------------------------------- */
async function handleFilter(body, env) {
  const query = (body.query || "").toString().trim();
  if (!query) return json({ error: "Missing query" }, 400);

  const system =
    "You convert a user's natural-language description of which video streams they want " +
    "into a JSON object. Output ONLY the JSON object, no prose or markdown. " +
    "Use exactly these keys (omit a key if not implied): " +
    '"minQuality" (one of "SD","720p","1080p","4K"), ' +
    '"maxSizeGB" (number, gigabytes), ' +
    '"cachedOnly" (boolean — true if they want instantly playable / cached / debrid-cached only), ' +
    '"language" (uppercase 2-letter tag like "EN","ES","FR" for the audio language), ' +
    '"codecPreferred" (boolean — true if they want efficient codecs like HEVC/H.265/AV1), ' +
    '"hdrOnly" (boolean — true if they want HDR/Dolby Vision only). ' +
    "Example: for 'cached 1080p under 8GB english h265' output " +
    '{"minQuality":"1080p","maxSizeGB":8,"cachedOnly":true,"language":"EN","codecPreferred":true}.';

  const content = await callClaude(env, system, query, 512);
  const filter = extractJSONObject(content) || {};
  return json({ filter });
}

/* ----------------------------------------------------------------------------
 * /troubleshoot — playback error -> plain-language diagnosis
 *   Request:  { "error": "VLC: unsupported codec", "context": { engine, source,
 *               container, host } }   (context optional)
 *   Response: { "cause": "...", "advice": "...",
 *               "suggestedAction": "tryOtherEngine|chooseDifferentStream|checkSMB|checkAddons|none" }
 * -------------------------------------------------------------------------- */
async function handleTroubleshoot(body, env) {
  const error = (body.error || "").toString().trim();
  if (!error) return json({ error: "Missing error" }, 400);
  const context = body.context ? JSON.stringify(body.context) : "none";

  const system =
    "You are a playback troubleshooting assistant for a video app that plays via AVPlayer " +
    "(Apple) and VLC, from sources like Real-Debrid, Stremio-style addons, SMB shares, and " +
    "direct URLs. Given an error message and optional context, explain the likely cause in one " +
    "or two plain sentences a non-technical user understands, then give one concrete next step. " +
    "Output ONLY a JSON object with keys: " +
    '"cause" (short plain-language explanation), ' +
    '"advice" (one concrete next step), ' +
    '"suggestedAction" (one of "tryOtherEngine","chooseDifferentStream","checkSMB","checkAddons","none"). ' +
    "Guidance: codec/format errors -> tryOtherEngine (suggest VLC). Expired/timeout/no-stream -> " +
    "chooseDifferentStream. SMB login/permission errors -> checkSMB. Addon-not-responding -> checkAddons.";

  const userMsg = `Error: ${error}\nContext: ${context}`;
  const content = await callClaude(env, system, userMsg, 512);
  const obj = extractJSONObject(content) || {
    cause: "Something went wrong during playback.",
    advice: "Try a different stream or the other player.",
    suggestedAction: "chooseDifferentStream",
  };
  return json(obj);
}

/* ------------------------------- helpers --------------------------------- */

async function callClaude(env, system, userText, maxTokens) {
  const res = await fetch(ANTHROPIC_URL, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": env.ANTHROPIC_API_KEY,
      "anthropic-version": ANTHROPIC_VERSION,
    },
    body: JSON.stringify({
      model: env.MODEL || DEFAULT_MODEL,
      max_tokens: maxTokens,
      system,
      messages: [{ role: "user", content: userText }],
    }),
  });

  if (!res.ok) {
    const detail = await res.text().catch(() => "");
    throw new Error(`Anthropic ${res.status}: ${detail.slice(0, 300)}`);
  }

  const data = await res.json();
  // Concatenate all text blocks from the response.
  return (data.content || [])
    .filter((b) => b.type === "text")
    .map((b) => b.text)
    .join("\n")
    .trim();
}

/** Pulls a JSON array of strings out of model output, tolerating stray prose/fences. */
function extractStringArray(text) {
  const cleaned = stripFences(text);
  // Try direct parse first.
  try {
    const v = JSON.parse(cleaned);
    if (Array.isArray(v)) return v.map(String).filter(Boolean);
  } catch {}
  // Fall back to the first [...] block.
  const m = cleaned.match(/\[[\s\S]*\]/);
  if (m) {
    try {
      const v = JSON.parse(m[0]);
      if (Array.isArray(v)) return v.map(String).filter(Boolean);
    } catch {}
  }
  // Last resort: split lines that look like list items.
  return cleaned
    .split("\n")
    .map((l) => l.replace(/^[-*\d.\s"]+/, "").replace(/[",]+$/, "").trim())
    .filter((l) => l.length > 0 && l.length < 120)
    .slice(0, 20);
}

/** Pulls a JSON object out of model output, tolerating stray prose/fences. */
function extractJSONObject(text) {
  const cleaned = stripFences(text);
  try {
    return JSON.parse(cleaned);
  } catch {}
  const m = cleaned.match(/\{[\s\S]*\}/);
  if (m) {
    try {
      return JSON.parse(m[0]);
    } catch {}
  }
  return null;
}

function stripFences(text) {
  return (text || "").replace(/```json/gi, "").replace(/```/g, "").trim();
}

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
  };
}

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json", ...corsHeaders() },
  });
}
