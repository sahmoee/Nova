/**
 * Astra AI Worker  (single-file, paste-into-Cloudflare-dashboard version)
 * ------------------------------------------------------------------------
 * Paste this whole file into the Cloudflare Worker editor and click Deploy.
 * No wrangler, no extra files needed.
 *
 * Before it works, add ONE secret in the dashboard:
 *   Workers & Pages > your worker > Settings > Variables and Secrets
 *   Add a secret (encrypted) named:  ANTHROPIC_API_KEY   = your Anthropic API key
 *
 * Optional secrets / variables:
 *   FRAMETV_SHARED_TOKEN (secret) - if set, callers must send
 *                                   Authorization: Bearer <token>. Leave UNSET for now
 *                                   (the app doesn't send it yet).
 *   MODEL (plaintext variable)    - defaults to claude-sonnet-4-6 if not set.
 *
 * Then copy the Worker's URL into the app: Settings > AI Search > Worker URL.
 *
 * The app posts { "query": "..." } to the root URL and expects { "titles": [...] }.
 * That's preserved here. Extra endpoints (/filter, /troubleshoot, /health) are additive.
 */

const DEFAULT_MODEL = "claude-sonnet-4-6";
const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, "") || "/";

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors() });
    }

    if (request.method === "GET" && path === "/health") {
      return json({ ok: true, model: env.MODEL || DEFAULT_MODEL });
    }

    // GET /diag — makes a REAL Anthropic call and reports the true result/error in the
    // browser. Use this to find out why title requests fail when /health passes.
    // It reveals whether the key is present and whether Anthropic accepts it.
    if (request.method === "GET" && path === "/diag") {
      const out = {
        hasKey: !!env.ANTHROPIC_API_KEY,
        keyPrefix: env.ANTHROPIC_API_KEY ? env.ANTHROPIC_API_KEY.slice(0, 7) + "…" : null,
        model: env.MODEL || DEFAULT_MODEL,
        sharedTokenSet: !!env.FRAMETV_SHARED_TOKEN,
      };
      if (!env.ANTHROPIC_API_KEY) {
        return json({ ...out, step: "no-key", advice: "Add the ANTHROPIC_API_KEY secret and redeploy." }, 200);
      }
      try {
        const res = await fetch(ANTHROPIC_URL, {
          method: "POST",
          headers: {
            "content-type": "application/json",
            "x-api-key": env.ANTHROPIC_API_KEY,
            "anthropic-version": ANTHROPIC_VERSION,
          },
          body: JSON.stringify({
            model: env.MODEL || DEFAULT_MODEL,
            max_tokens: 64,
            messages: [{ role: "user", content: 'Reply with the JSON array ["ok"] and nothing else.' }],
          }),
        });
        const raw = await res.text();
        return json({
          ...out,
          step: res.ok ? "anthropic-ok" : "anthropic-error",
          anthropicStatus: res.status,
          anthropicBody: raw.slice(0, 600),
        }, 200);
      } catch (e) {
        return json({ ...out, step: "fetch-threw", detail: String(e) }, 200);
      }
    }

    if (request.method !== "POST") {
      return json({ error: "POST only" }, 405);
    }

    // Optional shared-token gate (only enforced if you set FRAMETV_SHARED_TOKEN).
    if (env.FRAMETV_SHARED_TOKEN) {
      const token = (request.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
      if (token !== env.FRAMETV_SHARED_TOKEN) return json({ error: "Unauthorized" }, 401);
    }

    // --- Snapshot sharing (peer-to-peer restore codes) ---------------------
    // These endpoints let one person share their backup snapshot with another via a
    // short code. They do NOT need the Anthropic key, so they're handled before that
    // check. They require a KV namespace bound as SNAPSHOTS (see wrangler.toml).
    if (path === "/share/create" || path === "/share/fetch") {
      let shareBody;
      try {
        shareBody = await request.json();
      } catch {
        return json({ error: "Invalid JSON body" }, 400);
      }
      try {
        return path === "/share/create"
          ? await handleShareCreate(shareBody, env)
          : await handleShareFetch(shareBody, env);
      } catch (err) {
        return json({ error: "Share error", detail: String(err) }, 502);
      }
    }

    if (!env.ANTHROPIC_API_KEY) {
      return json({ error: "Worker is missing ANTHROPIC_API_KEY secret" }, 500);
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

/* --- Snapshot sharing ------------------------------------------------------
 * POST /share/create  { snapshot: "<base64>", contents: <int>, ttlDays?: <int> }
 *   -> { code: "ABC123", expiresAt: "<iso>" }
 * POST /share/fetch   { code: "ABC123" }
 *   -> { snapshot: "<base64>", contents: <int> }  (404 if unknown/expired)
 *
 * Requires a KV namespace bound as SNAPSHOTS. Codes are short, human-readable, and
 * expire automatically. The snapshot is stored exactly as the app sent it (the app
 * decides what it contains -- preferences, sources, addons, and optionally secrets).
 */

// Unambiguous alphabet (no 0/O/1/I) for easy reading/typing over the phone.
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const CODE_LENGTH = 6;
const MAX_SNAPSHOT_BYTES = 4 * 1024 * 1024; // 4 MB of base64 -- snapshots are small JSON.

function makeCode() {
  let out = "";
  const bytes = crypto.getRandomValues(new Uint8Array(CODE_LENGTH));
  for (let i = 0; i < CODE_LENGTH; i++) {
    out += CODE_ALPHABET[bytes[i] % CODE_ALPHABET.length];
  }
  return out;
}

async function handleShareCreate(body, env) {
  if (!env.SNAPSHOTS) {
    return json({ error: "Sharing not enabled: bind a KV namespace named SNAPSHOTS." }, 501);
  }
  const snapshot = (body.snapshot || "").toString();
  if (!snapshot) return json({ error: "Missing snapshot" }, 400);
  if (snapshot.length > MAX_SNAPSHOT_BYTES) {
    return json({ error: "Snapshot too large" }, 413);
  }
  const contents = Number.isInteger(body.contents) ? body.contents : 0;
  const ttlDays = Math.min(Math.max(parseInt(body.ttlDays, 10) || 7, 1), 30);
  const ttlSeconds = ttlDays * 86400;

  // Retry a few times in the unlikely event of a code collision.
  let code = "";
  for (let attempt = 0; attempt < 5; attempt++) {
    code = makeCode();
    const existing = await env.SNAPSHOTS.get(code);
    if (!existing) break;
  }
  const record = JSON.stringify({ snapshot, contents, createdAt: new Date().toISOString() });
  await env.SNAPSHOTS.put(code, record, { expirationTtl: ttlSeconds });
  const expiresAt = new Date(Date.now() + ttlSeconds * 1000).toISOString();
  return json({ code, expiresAt });
}

async function handleShareFetch(body, env) {
  if (!env.SNAPSHOTS) {
    return json({ error: "Sharing not enabled: bind a KV namespace named SNAPSHOTS." }, 501);
  }
  const code = (body.code || "").toString().trim().toUpperCase();
  if (!code) return json({ error: "Missing code" }, 400);
  const record = await env.SNAPSHOTS.get(code);
  if (!record) return json({ error: "Code not found or expired" }, 404);
  try {
    const parsed = JSON.parse(record);
    return json({ snapshot: parsed.snapshot, contents: parsed.contents || 0 });
  } catch {
    return json({ error: "Corrupt snapshot record" }, 500);
  }
}

/* --- /  and  /titles : { query } -> { titles: [...] } --------------------- */
async function handleTitles(body, env) {
  const query = (body.query || "").toString().trim();
  if (!query) return json({ error: "Missing query" }, 400);

  const system =
    "You are a film and TV recommendation engine for a media app. " +
    "Given a user's request, reply with real, existing movie or TV show titles that best match. " +
    "Rules: (1) Output ONLY a JSON array of strings — no prose, no markdown, no object. " +
    "(2) Each string is a single real title as it appears on TMDB (no year, no extra words). " +
    "(3) If the user asks for a specific count (e.g. '5 movies'), return exactly that many; " +
    "otherwise return 12 to 20. (4) Prefer well-known, findable titles; never invent titles. " +
    "(5) No duplicates.";

  const text = await callClaude(env, system, query, 1024);
  return json({ titles: extractStringArray(text) });
}

/* --- /filter : { query } -> { filter: {...} } ----------------------------- */
async function handleFilter(body, env) {
  const query = (body.query || "").toString().trim();
  if (!query) return json({ error: "Missing query" }, 400);

  const system =
    "Convert a user's natural-language description of which video streams they want into a JSON object. " +
    "Output ONLY the JSON object — no prose or markdown. Use exactly these keys (omit a key if not implied): " +
    '"minQuality" (one of "SD","720p","1080p","4K"), "maxSizeGB" (number), ' +
    '"cachedOnly" (boolean — instantly playable / cached / debrid-cached only), ' +
    '"language" (uppercase 2-letter audio tag like "EN","ES","FR"), ' +
    '"codecPreferred" (boolean — efficient codecs like HEVC/H.265/AV1), ' +
    '"hdrOnly" (boolean — HDR/Dolby Vision only). ' +
    'Example: "cached 1080p under 8GB english h265" -> ' +
    '{"minQuality":"1080p","maxSizeGB":8,"cachedOnly":true,"language":"EN","codecPreferred":true}.';

  const text = await callClaude(env, system, query, 512);
  return json({ filter: extractJSONObject(text) || {} });
}

/* --- /troubleshoot : { error, context? } -> { cause, advice, suggestedAction } */
async function handleTroubleshoot(body, env) {
  const error = (body.error || "").toString().trim();
  if (!error) return json({ error: "Missing error" }, 400);
  const context = body.context ? JSON.stringify(body.context) : "none";

  const system =
    "You are a playback troubleshooting assistant for a video app that plays via AVPlayer (Apple) and VLC, " +
    "from Real-Debrid, Stremio-style addons, SMB shares, and direct URLs. Given an error and optional context, " +
    "explain the likely cause in one or two plain sentences a non-technical user understands, then one concrete next step. " +
    "Output ONLY a JSON object with keys: \"cause\", \"advice\", and " +
    '"suggestedAction" (one of "tryOtherEngine","chooseDifferentStream","checkSMB","checkAddons","none"). ' +
    "Codec/format errors -> tryOtherEngine (suggest VLC). Expired/timeout/no-stream -> chooseDifferentStream. " +
    "SMB login/permission errors -> checkSMB. Addon not responding -> checkAddons.";

  const text = await callClaude(env, system, `Error: ${error}\nContext: ${context}`, 512);
  return json(
    extractJSONObject(text) || {
      cause: "Something went wrong during playback.",
      advice: "Try a different stream or the other player.",
      suggestedAction: "chooseDifferentStream",
    }
  );
}

/* --------------------------------- helpers -------------------------------- */
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
  return (data.content || [])
    .filter((b) => b.type === "text")
    .map((b) => b.text)
    .join("\n")
    .trim();
}

function extractStringArray(text) {
  const cleaned = stripFences(text);
  try {
    const v = JSON.parse(cleaned);
    if (Array.isArray(v)) return v.map(String).filter(Boolean);
  } catch {}
  const m = cleaned.match(/\[[\s\S]*\]/);
  if (m) {
    try {
      const v = JSON.parse(m[0]);
      if (Array.isArray(v)) return v.map(String).filter(Boolean);
    } catch {}
  }
  return cleaned
    .split("\n")
    .map((l) => l.replace(/^[-*\d.\s"]+/, "").replace(/[",]+$/, "").trim())
    .filter((l) => l.length > 0 && l.length < 120)
    .slice(0, 20);
}

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

function cors() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
  };
}

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json", ...cors() },
  });
}
