/**
 * Astra AI + Sharing Worker  (single-file, paste-into-Cloudflare-dashboard version)
 * --------------------------------------------------------------------------------
 * Paste this whole file into the Cloudflare Worker editor and click Deploy, or deploy
 * with wrangler. worker/worker.js is kept byte-identical to this file (release_check.sh
 * enforces it).
 *
 * Secrets / variables (Workers & Pages > your worker > Settings > Variables):
 *   ANTHROPIC_API_KEY (secret)   - required for AI endpoints (/titles /filter /troubleshoot).
 *   ASTRA_SHARED_TOKEN (secret)   - if set, ALL POST calls and /diag require
 *                                     Authorization: Bearer <token>. The app stores this in
 *                                     Keychain and sends it. Strongly recommended in production.
 *   MODEL (plaintext variable)    - defaults to claude-sonnet-4-6.
 *
 * KV binding (for sharing + rate limiting):
 *   SNAPSHOTS - a KV namespace. Share codes and rate-limit counters live here.
 *
 * Endpoints:
 *   GET  /health                 -> { ok }
 *   GET  /diag                   -> sanitized capability state (token-gated; no secrets)
 *   POST /titles (or /)          -> { titles: [...] }
 *   POST /filter                 -> { filter: {...} }
 *   POST /troubleshoot           -> { cause, advice, suggestedAction }
 *   POST /share/create           -> { code, expiresAt }   (stores opaque ciphertext)
 *   POST /share/fetch            -> { snapshot, contents, enc }  (ONE-TIME: deletes on read)
 */

const DEFAULT_MODEL = "claude-sonnet-4-6";
const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";

// Limits (strict payload validation).
const MAX_BODY_BYTES = 6 * 1024 * 1024;      // hard cap on any request body
const MAX_SNAPSHOT_BYTES = 4 * 1024 * 1024;  // share payload cap
const MAX_QUERY_LEN = 2000;                  // AI query / error string cap
const ANTHROPIC_TIMEOUT_MS = 25000;
const KV_TIMEOUT_MS = 5000;

// Per-endpoint rate limits: [maxRequests, windowSeconds], keyed by client IP.
const RATE_LIMITS = {
  ai:      [30, 60],       // 30 AI calls per minute per IP
  create:  [10, 3600],     // 10 share-code creations per hour per IP
  fetch:   [40, 3600],     // 40 code lookups per hour per IP (enumeration guard)
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, "") || "/";
    const ip = request.headers.get("CF-Connecting-IP") || "unknown";

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors() });
    }

    if (request.method === "GET" && path === "/health") {
      return json({ ok: true, model: env.MODEL || DEFAULT_MODEL });
    }

    // GET /diag — sanitized capability state only. Token-gated when a shared token is
    // configured. Never exposes the key prefix or raw upstream error bodies.
    if (request.method === "GET" && path === "/diag") {
      if (env.ASTRA_SHARED_TOKEN && !authorized(request, env)) {
        return json({ error: "Unauthorized" }, 401);
      }
      const out = {
        hasKey: !!env.ANTHROPIC_API_KEY,
        model: env.MODEL || DEFAULT_MODEL,
        sharedTokenSet: !!env.ASTRA_SHARED_TOKEN,
        sharingEnabled: !!env.SNAPSHOTS,
      };
      if (!env.ANTHROPIC_API_KEY) {
        return json({ ...out, step: "no-key" }, 200);
      }
      try {
        const res = await withTimeout(
          fetchAnthropic(env, "Reply with the JSON array [\"ok\"] and nothing else.", 64),
          ANTHROPIC_TIMEOUT_MS
        );
        // Report only the status code — not the upstream body (which can leak details).
        return json({ ...out, step: res.ok ? "anthropic-ok" : "anthropic-error", anthropicStatus: res.status }, 200);
      } catch (e) {
        return json({ ...out, step: "anthropic-unreachable" }, 200);
      }
    }

    if (request.method !== "POST") {
      return json({ error: "POST only" }, 405);
    }

    // Auth gate (enforced only if ASTRA_SHARED_TOKEN is set).
    if (env.ASTRA_SHARED_TOKEN && !authorized(request, env)) {
      return json({ error: "Unauthorized" }, 401);
    }

    // Content-type + body-size guard, then parse once.
    const ct = request.headers.get("Content-Type") || "";
    if (!ct.toLowerCase().includes("application/json")) {
      return json({ error: "Expected application/json" }, 415);
    }
    let raw;
    try {
      raw = await request.text();
    } catch {
      return json({ error: "Unreadable body" }, 400);
    }
    if (raw.length > MAX_BODY_BYTES) {
      return json({ error: "Body too large" }, 413);
    }
    let body;
    try {
      body = JSON.parse(raw);
    } catch {
      return json({ error: "Invalid JSON body" }, 400);
    }
    if (typeof body !== "object" || body === null || Array.isArray(body)) {
      return json({ error: "Body must be a JSON object" }, 400);
    }

    // --- Snapshot sharing -------------------------------------------------
    if (path === "/share/create" || path === "/share/fetch") {
      const bucket = path === "/share/create" ? "create" : "fetch";
      if (!(await underRateLimit(env, ip, bucket))) {
        return json({ error: "Rate limit exceeded. Try again later." }, 429);
      }
      try {
        return path === "/share/create"
          ? await handleShareCreate(body, env)
          : await handleShareFetch(body, env);
      } catch {
        return json({ error: "Share error" }, 502);
      }
    }

    // --- AI endpoints -----------------------------------------------------
    if (!env.ANTHROPIC_API_KEY) {
      return json({ error: "Worker is missing ANTHROPIC_API_KEY secret" }, 500);
    }
    if (!(await underRateLimit(env, ip, "ai"))) {
      return json({ error: "Rate limit exceeded. Try again shortly." }, 429);
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
    } catch {
      return json({ error: "Worker error" }, 502);
    }
  },
};

/* --------------------------- auth + rate limiting ------------------------- */

function authorized(request, env) {
  const token = (request.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  return !!token && token === env.ASTRA_SHARED_TOKEN;
}

// Best-effort sliding-window rate limit backed by the SNAPSHOTS KV. Fails OPEN if KV
// is not bound (so AI still works without sharing configured).
async function underRateLimit(env, ip, bucket) {
  if (!env.SNAPSHOTS) return true;
  const [limit, windowSec] = RATE_LIMITS[bucket] || RATE_LIMITS.ai;
  const slot = Math.floor(Date.now() / 1000 / windowSec);
  const key = `rl:${bucket}:${ip}:${slot}`;
  try {
    const current = parseInt((await withTimeout(env.SNAPSHOTS.get(key), KV_TIMEOUT_MS)) || "0", 10);
    if (current >= limit) return false;
    await withTimeout(
      env.SNAPSHOTS.put(key, String(current + 1), { expirationTtl: windowSec + 60 }),
      KV_TIMEOUT_MS
    );
    return true;
  } catch {
    return true; // never block real users on a KV hiccup
  }
}

/* ------------------------------ share storage ---------------------------- */
/*
 * The app encrypts the snapshot on-device (AES-GCM) and sends opaque ciphertext, so the
 * Worker never sees plaintext. `snapshot` is base64 ciphertext; `enc` marks it encrypted.
 * Fetch is ONE-TIME: the record is deleted on first successful read.
 */

const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no 0/O/1/I
const CODE_LENGTH = 6;

function makeCode() {
  let out = "";
  const bytes = crypto.getRandomValues(new Uint8Array(CODE_LENGTH));
  for (let i = 0; i < CODE_LENGTH; i++) out += CODE_ALPHABET[bytes[i] % CODE_ALPHABET.length];
  return out;
}

async function handleShareCreate(body, env) {
  if (!env.SNAPSHOTS) {
    return json({ error: "Sharing not enabled: bind a KV namespace named SNAPSHOTS." }, 501);
  }
  const snapshot = typeof body.snapshot === "string" ? body.snapshot : "";
  if (!snapshot) return json({ error: "Missing snapshot" }, 400);
  if (snapshot.length > MAX_SNAPSHOT_BYTES) return json({ error: "Snapshot too large" }, 413);
  if (!/^[A-Za-z0-9+/=]+$/.test(snapshot)) return json({ error: "Snapshot must be base64" }, 400);
  const contents = Number.isInteger(body.contents) ? body.contents : 0;
  const enc = body.enc === true;
  const ttlDays = Math.min(Math.max(parseInt(body.ttlDays, 10) || 7, 1), 30);
  const ttlSeconds = ttlDays * 86400;

  let code = "";
  for (let attempt = 0; attempt < 5; attempt++) {
    code = makeCode();
    const existing = await withTimeout(env.SNAPSHOTS.get(code), KV_TIMEOUT_MS);
    if (!existing) break;
  }
  const record = JSON.stringify({ snapshot, contents, enc, createdAt: new Date().toISOString() });
  await withTimeout(env.SNAPSHOTS.put(code, record, { expirationTtl: ttlSeconds }), KV_TIMEOUT_MS);
  return json({ code, expiresAt: new Date(Date.now() + ttlSeconds * 1000).toISOString() });
}

async function handleShareFetch(body, env) {
  if (!env.SNAPSHOTS) {
    return json({ error: "Sharing not enabled: bind a KV namespace named SNAPSHOTS." }, 501);
  }
  const code = (typeof body.code === "string" ? body.code : "").trim().toUpperCase();
  if (!code || code.length > 16 || !/^[A-Z0-9]+$/.test(code)) {
    return json({ error: "Invalid code" }, 400);
  }
  const record = await withTimeout(env.SNAPSHOTS.get(code), KV_TIMEOUT_MS);
  if (!record) return json({ error: "Code not found or expired" }, 404);
  // One-time retrieval: delete before returning so a code can't be reused/enumerated.
  await withTimeout(env.SNAPSHOTS.delete(code), KV_TIMEOUT_MS).catch(() => {});
  try {
    const parsed = JSON.parse(record);
    return json({ snapshot: parsed.snapshot, contents: parsed.contents || 0, enc: parsed.enc === true });
  } catch {
    return json({ error: "Corrupt snapshot record" }, 500);
  }
}

/* ------------------------------- AI endpoints ---------------------------- */

async function handleTitles(body, env) {
  const query = str(body.query);
  if (!query) return json({ error: "Missing query" }, 400);
  if (query.length > MAX_QUERY_LEN) return json({ error: "Query too long" }, 413);

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

async function handleFilter(body, env) {
  const query = str(body.query);
  if (!query) return json({ error: "Missing query" }, 400);
  if (query.length > MAX_QUERY_LEN) return json({ error: "Query too long" }, 413);

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

async function handleTroubleshoot(body, env) {
  const error = str(body.error);
  if (!error) return json({ error: "Missing error" }, 400);
  if (error.length > MAX_QUERY_LEN) return json({ error: "Error too long" }, 413);
  const context = body.context ? JSON.stringify(body.context).slice(0, MAX_QUERY_LEN) : "none";

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

function str(v) {
  return (v === undefined || v === null ? "" : String(v)).trim();
}

// Rejects if the promise doesn't settle within ms. Works for both fetch (with signal)
// and KV (which has no signal — Promise.race still bounds our own wait).
function withTimeout(promise, ms) {
  return Promise.race([
    promise,
    new Promise((_, reject) => setTimeout(() => reject(new Error("timeout")), ms)),
  ]);
}

function fetchAnthropic(env, userText, maxTokens, system) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), ANTHROPIC_TIMEOUT_MS);
  const payload = { model: env.MODEL || DEFAULT_MODEL, max_tokens: maxTokens, messages: [{ role: "user", content: userText }] };
  if (system) payload.system = system;
  return fetch(ANTHROPIC_URL, {
    method: "POST",
    signal: controller.signal,
    headers: {
      "content-type": "application/json",
      "x-api-key": env.ANTHROPIC_API_KEY,
      "anthropic-version": ANTHROPIC_VERSION,
    },
    body: JSON.stringify(payload),
  }).finally(() => clearTimeout(timer));
}

async function callClaude(env, system, userText, maxTokens) {
  const res = await withTimeout(fetchAnthropic(env, userText, maxTokens, system), ANTHROPIC_TIMEOUT_MS + 1000);
  if (!res.ok) {
    // Do not surface the upstream body to callers.
    throw new Error(`Anthropic ${res.status}`);
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
