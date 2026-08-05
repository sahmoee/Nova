import { DurableObject } from "cloudflare:workers";

const DEFAULT_MODEL = "claude-sonnet-4-6";
const DEFAULT_SERVICE_NAME = "nova-ai-worker";
const PRODUCT_NAME = "Nova";
const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";
const MAX_BODY_BYTES = 6 * 1024 * 1024;
const MAX_SNAPSHOT_BYTES = 4 * 1024 * 1024;
const MAX_QUERY_LENGTH = 2_000;
const ANTHROPIC_TIMEOUT_MS = 25_000;
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const CODE_LENGTH = 8;

type RateBucket = "ai" | "create" | "fetch";
const RATE_LIMITS: Record<RateBucket, readonly [limit: number, windowSeconds: number]> = {
  ai: [30, 60],
  create: [10, 3_600],
  fetch: [40, 3_600],
};

interface ShareRecord {
  snapshot: string;
  contents: number;
  enc: boolean;
  createdAt: string;
  expiresAt: number;
}

interface WorkerSecrets {
  ANTHROPIC_API_KEY?: string;
  NOVA_SHARED_TOKEN?: string;
}

type WorkerEnv = Env & WorkerSecrets;

type FilterResponse = {
  minQuality?: "SD" | "720p" | "1080p" | "4K";
  maxSizeGB?: number;
  cachedOnly?: boolean;
  language?: string;
  codecPreferred?: boolean;
  hdrOnly?: boolean;
};

type TroubleshootAction = "tryOtherEngine" | "chooseDifferentStream" | "checkSMB" | "checkAddons" | "none";

export class ShareStore extends DurableObject<WorkerEnv> {
  constructor(ctx: DurableObjectState, env: WorkerEnv) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => {
      this.ctx.storage.sql.exec(`
        CREATE TABLE IF NOT EXISTS share_record (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          snapshot TEXT NOT NULL,
          contents INTEGER NOT NULL,
          enc INTEGER NOT NULL,
          created_at TEXT NOT NULL,
          expires_at INTEGER NOT NULL
        )
      `);
    });
  }

  async create(record: ShareRecord): Promise<boolean> {
    const existing = this.ctx.storage.sql
      .exec<{ expires_at: number }>("SELECT expires_at FROM share_record WHERE id = 1")
      .toArray()[0];
    if (existing && existing.expires_at > Date.now()) return false;
    this.ctx.storage.sql.exec("DELETE FROM share_record");
    this.ctx.storage.sql.exec(
      "INSERT INTO share_record (id, snapshot, contents, enc, created_at, expires_at) VALUES (1, ?, ?, ?, ?, ?)",
      record.snapshot,
      record.contents,
      record.enc ? 1 : 0,
      record.createdAt,
      record.expiresAt,
    );
    await this.ctx.storage.setAlarm(record.expiresAt);
    return true;
  }

  async take(): Promise<ShareRecord | null> {
    const row = this.ctx.storage.sql
      .exec<{
        snapshot: string;
        contents: number;
        enc: number;
        created_at: string;
        expires_at: number;
      }>("SELECT snapshot, contents, enc, created_at, expires_at FROM share_record WHERE id = 1")
      .toArray()[0];
    if (!row) return null;
    this.ctx.storage.sql.exec("DELETE FROM share_record WHERE id = 1");
    await this.ctx.storage.deleteAlarm();
    if (row.expires_at <= Date.now()) return null;
    return {
      snapshot: row.snapshot,
      contents: row.contents,
      enc: row.enc === 1,
      createdAt: row.created_at,
      expiresAt: row.expires_at,
    };
  }

  override async alarm(): Promise<void> {
    this.ctx.storage.sql.exec("DELETE FROM share_record");
  }
}

export class RateLimiter extends DurableObject<WorkerEnv> {
  constructor(ctx: DurableObjectState, env: WorkerEnv) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => {
      this.ctx.storage.sql.exec(`
        CREATE TABLE IF NOT EXISTS rate_state (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          window_start INTEGER NOT NULL,
          count INTEGER NOT NULL
        )
      `);
    });
  }

  consume(now: number, limit: number, windowSeconds: number): boolean {
    const windowMs = windowSeconds * 1_000;
    const windowStart = Math.floor(now / windowMs) * windowMs;
    const row = this.ctx.storage.sql
      .exec<{ window_start: number; count: number }>(
        "SELECT window_start, count FROM rate_state WHERE id = 1",
      )
      .toArray()[0];
    const count = row?.window_start === windowStart ? row.count : 0;
    if (count >= limit) return false;
    this.ctx.storage.sql.exec(
      "INSERT INTO rate_state (id, window_start, count) VALUES (1, ?, ?) ON CONFLICT(id) DO UPDATE SET window_start = excluded.window_start, count = excluded.count",
      windowStart,
      count + 1,
    );
    return true;
  }
}

export default {
  async fetch(request, env): Promise<Response> {
    const startedAt = Date.now();
    const requestId = crypto.randomUUID();
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, "") || "/";

    try {
      if (request.method === "OPTIONS") {
        return new Response(null, { status: 204, headers: responseHeaders(request, env) });
      }
      if (request.method === "GET" && path === "/health") {
        return json(
          {
            ok: true,
            service: env.SERVICE_NAME || DEFAULT_SERVICE_NAME,
            product: PRODUCT_NAME,
            model: env.MODEL || DEFAULT_MODEL,
          },
          200,
          request,
          env,
        );
      }
      if (request.method === "GET" && path === "/diag") {
        if (env.NOVA_SHARED_TOKEN && !(await authorized(request, env.NOVA_SHARED_TOKEN))) {
          return json({ error: "Unauthorized" }, 401, request, env);
        }
        return handleDiagnostics(request, env);
      }
      if (request.method !== "POST") {
        return json({ error: "Not found" }, 404, request, env, { Allow: "GET, POST, OPTIONS" });
      }
      if (env.NOVA_SHARED_TOKEN && !(await authorized(request, env.NOVA_SHARED_TOKEN))) {
        return json({ error: "Unauthorized" }, 401, request, env);
      }

      const knownPaths = new Set(["/", "/titles", "/filter", "/troubleshoot", "/share/create", "/share/fetch"]);
      if (!knownPaths.has(path)) return json({ error: "Not found" }, 404, request, env);

      const contentType = request.headers.get("Content-Type")?.toLowerCase() ?? "";
      if (!contentType.includes("application/json")) {
        return json({ error: "Expected application/json" }, 415, request, env);
      }
      const bodyResult = await readJSONObject(request, MAX_BODY_BYTES);
      if (!bodyResult.ok) return json({ error: bodyResult.error }, bodyResult.status, request, env);
      const body = bodyResult.value;
      const ip = request.headers.get("CF-Connecting-IP") || "unknown";

      if (path === "/share/create" || path === "/share/fetch") {
        const bucket: RateBucket = path === "/share/create" ? "create" : "fetch";
        if (!(await consumeRateLimit(env, ip, bucket))) {
          return json({ error: "Rate limit exceeded. Try again later." }, 429, request, env);
        }
        return path === "/share/create"
          ? handleShareCreate(body, request, env)
          : handleShareFetch(body, request, env);
      }

      if (!env.ANTHROPIC_API_KEY) {
        return json({ error: "Worker is missing ANTHROPIC_API_KEY secret" }, 503, request, env);
      }
      if (!(await consumeRateLimit(env, ip, "ai"))) {
        return json({ error: "Rate limit exceeded. Try again shortly." }, 429, request, env);
      }
      if (path === "/" || path === "/titles") return handleTitles(body, request, env);
      if (path === "/filter") return handleFilter(body, request, env);
      return handleTroubleshoot(body, request, env);
    } catch (error) {
      log("error", "request_failed", {
        requestId,
        path,
        method: request.method,
        durationMs: Date.now() - startedAt,
        error: errorMessage(error),
      });
      return json({ error: "Service temporarily unavailable", requestId }, 503, request, env);
    } finally {
      log("info", "request_complete", {
        requestId,
        path,
        method: request.method,
        durationMs: Date.now() - startedAt,
      });
    }
  },
} satisfies ExportedHandler<WorkerEnv>;

async function handleDiagnostics(request: Request, env: WorkerEnv): Promise<Response> {
  const out = {
    service: env.SERVICE_NAME || DEFAULT_SERVICE_NAME,
    product: PRODUCT_NAME,
    hasKey: Boolean(env.ANTHROPIC_API_KEY),
    model: env.MODEL || DEFAULT_MODEL,
    sharedTokenSet: Boolean(env.NOVA_SHARED_TOKEN),
    sharingEnabled: Boolean(env.SHARE_STORE),
  };
  if (!env.ANTHROPIC_API_KEY) return json({ ...out, step: "no-key" }, 200, request, env);
  try {
    const response = await fetchAnthropic(env, "Reply with the JSON array [\"ok\"] and nothing else.", 64);
    return json(
      { ...out, step: response.ok ? "anthropic-ok" : "anthropic-error", anthropicStatus: response.status },
      200,
      request,
      env,
    );
  } catch {
    return json({ ...out, step: "anthropic-unreachable" }, 200, request, env);
  }
}

async function authorized(request: Request, expected: string): Promise<boolean> {
  const provided = (request.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  if (!provided) return false;
  const encoder = new TextEncoder();
  const [providedHash, expectedHash] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(provided)),
    crypto.subtle.digest("SHA-256", encoder.encode(expected)),
  ]);
  const left = new Uint8Array(providedHash);
  const right = new Uint8Array(expectedHash);
  let mismatch = left.byteLength ^ right.byteLength;
  for (let index = 0; index < left.byteLength; index += 1) {
    mismatch |= (left[index] ?? 0) ^ (right[index] ?? 0);
  }
  return mismatch === 0;
}

async function consumeRateLimit(env: WorkerEnv, ip: string, bucket: RateBucket): Promise<boolean> {
  const [limit, windowSeconds] = RATE_LIMITS[bucket];
  const stub = env.RATE_LIMITER.getByName(`${bucket}:${ip}`);
  return stub.consume(Date.now(), limit, windowSeconds);
}

async function handleShareCreate(body: Record<string, unknown>, request: Request, env: WorkerEnv): Promise<Response> {
  const snapshot = typeof body.snapshot === "string" ? body.snapshot : "";
  if (!snapshot) return json({ error: "Missing snapshot" }, 400, request, env);
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(snapshot) || snapshot.length % 4 !== 0) {
    return json({ error: "Snapshot must be valid base64" }, 400, request, env);
  }
  if (decodedBase64Length(snapshot) > MAX_SNAPSHOT_BYTES) {
    return json({ error: "Snapshot too large" }, 413, request, env);
  }
  const contents = Number.isInteger(body.contents) ? Number(body.contents) : 0;
  const enc = body.enc === true;
  const requestedDays = typeof body.ttlDays === "number" || typeof body.ttlDays === "string"
    ? Number.parseInt(String(body.ttlDays), 10)
    : 7;
  const ttlDays = Math.min(Math.max(Number.isFinite(requestedDays) ? requestedDays : 7, 1), 30);
  const expiresAt = Date.now() + ttlDays * 86_400_000;
  const record: ShareRecord = {
    snapshot,
    contents,
    enc,
    createdAt: new Date().toISOString(),
    expiresAt,
  };

  for (let attempt = 0; attempt < 8; attempt += 1) {
    const code = makeCode();
    const created = await env.SHARE_STORE.getByName(code).create(record);
    if (created) {
      return json({ code, expiresAt: new Date(expiresAt).toISOString() }, 200, request, env);
    }
  }
  return json({ error: "Could not allocate a share code. Try again." }, 503, request, env);
}

async function handleShareFetch(body: Record<string, unknown>, request: Request, env: WorkerEnv): Promise<Response> {
  const code = (typeof body.code === "string" ? body.code : "").trim().toUpperCase();
  if (!new RegExp(`^[A-Z2-9]{${CODE_LENGTH}}$`).test(code)) {
    return json({ error: "Invalid code" }, 400, request, env);
  }
  const record = await env.SHARE_STORE.getByName(code).take();
  if (!record) return json({ error: "Code not found or expired" }, 404, request, env);
  return json(
    { snapshot: record.snapshot, contents: record.contents, enc: record.enc },
    200,
    request,
    env,
  );
}

async function handleTitles(body: Record<string, unknown>, request: Request, env: WorkerEnv): Promise<Response> {
  const query = cleanString(body.query);
  if (!query) return json({ error: "Missing query" }, 400, request, env);
  if (query.length > MAX_QUERY_LENGTH) return json({ error: "Query too long" }, 413, request, env);
  const system =
    "You are a film and TV recommendation engine. Output only a JSON array of real TMDB title strings, without years or duplicates. Return the requested count, otherwise 12 to 20.";
  const text = await callClaude(env, system, query, 1_024);
  return json({ titles: extractStringArray(text) }, 200, request, env);
}

async function handleFilter(body: Record<string, unknown>, request: Request, env: WorkerEnv): Promise<Response> {
  const query = cleanString(body.query);
  if (!query) return json({ error: "Missing query" }, 400, request, env);
  if (query.length > MAX_QUERY_LENGTH) return json({ error: "Query too long" }, 413, request, env);
  const system =
    "Convert the request to JSON using only minQuality (SD,720p,1080p,4K), maxSizeGB, cachedOnly, language, codecPreferred, hdrOnly. Omit values not implied. Output JSON only.";
  const text = await callClaude(env, system, query, 512);
  return json({ filter: sanitizeFilter(extractJSONObject(text)) }, 200, request, env);
}

async function handleTroubleshoot(body: Record<string, unknown>, request: Request, env: WorkerEnv): Promise<Response> {
  const error = cleanString(body.error);
  if (!error) return json({ error: "Missing error" }, 400, request, env);
  if (error.length > MAX_QUERY_LENGTH) return json({ error: "Error too long" }, 413, request, env);
  const context = body.context === undefined ? "none" : JSON.stringify(body.context).slice(0, MAX_QUERY_LENGTH);
  const system =
    'Explain the playback error briefly. Output JSON only with cause, advice, suggestedAction. suggestedAction must be one of "tryOtherEngine", "chooseDifferentStream", "checkSMB", "checkAddons", "none".';
  const text = await callClaude(env, system, `Error: ${error}\nContext: ${context}`, 512);
  return json(sanitizeTroubleshoot(extractJSONObject(text)), 200, request, env);
}

async function readJSONObject(
  request: Request,
  maxBytes: number,
): Promise<
  | { ok: true; value: Record<string, unknown> }
  | { ok: false; error: string; status: number }
> {
  const declaredLength = Number(request.headers.get("Content-Length"));
  if (Number.isFinite(declaredLength) && declaredLength > maxBytes) {
    return { ok: false, error: "Body too large", status: 413 };
  }
  if (!request.body) return { ok: false, error: "Missing body", status: 400 };
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maxBytes) {
      await reader.cancel("body too large");
      return { ok: false, error: "Body too large", status: 413 };
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    const parsed: unknown = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
    if (!isRecord(parsed)) return { ok: false, error: "Body must be a JSON object", status: 400 };
    return { ok: true, value: parsed };
  } catch {
    return { ok: false, error: "Invalid JSON body", status: 400 };
  }
}

function decodedBase64Length(value: string): number {
  const padding = value.endsWith("==") ? 2 : value.endsWith("=") ? 1 : 0;
  return (value.length * 3) / 4 - padding;
}

function makeCode(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(CODE_LENGTH));
  return Array.from(bytes, (byte) => CODE_ALPHABET.charAt(byte & 31)).join("");
}

function cleanString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

async function fetchAnthropic(env: WorkerEnv, userText: string, maxTokens: number, system?: string): Promise<Response> {
  const apiKey = env.ANTHROPIC_API_KEY;
  if (!apiKey) throw new Error("ANTHROPIC_API_KEY is not configured");
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), ANTHROPIC_TIMEOUT_MS);
  try {
    const payload: Record<string, unknown> = {
      model: env.MODEL || DEFAULT_MODEL,
      max_tokens: maxTokens,
      messages: [{ role: "user", content: userText }],
    };
    if (system) payload.system = system;
    return await fetch(ANTHROPIC_URL, {
      method: "POST",
      signal: controller.signal,
      headers: {
        "content-type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": ANTHROPIC_VERSION,
      },
      body: JSON.stringify(payload),
    });
  } finally {
    clearTimeout(timer);
  }
}

async function callClaude(env: WorkerEnv, system: string, userText: string, maxTokens: number): Promise<string> {
  const response = await fetchAnthropic(env, userText, maxTokens, system);
  if (!response.ok) throw new Error(`Anthropic request failed (${response.status})`);
  const value: unknown = await response.json();
  if (!isRecord(value) || !Array.isArray(value.content)) throw new Error("Invalid Anthropic response");
  return value.content
    .filter(isRecord)
    .filter((block) => block.type === "text" && typeof block.text === "string")
    .map((block) => (typeof block.text === "string" ? block.text : ""))
    .join("\n")
    .trim();
}

function extractStringArray(text: string): string[] {
  const cleaned = stripFences(text);
  const candidates = [cleaned, cleaned.match(/\[[\s\S]*\]/)?.[0]].filter(
    (value): value is string => Boolean(value),
  );
  for (const candidate of candidates) {
    try {
      const parsed: unknown = JSON.parse(candidate);
      if (Array.isArray(parsed)) {
        return Array.from(
          new Set(parsed.filter((value): value is string => typeof value === "string").map((value) => value.trim())),
        )
          .filter((value) => value.length > 0 && value.length < 120)
          .slice(0, 20);
      }
    } catch {
      // Try the next bounded representation.
    }
  }
  return [];
}

function extractJSONObject(text: string): Record<string, unknown> | null {
  const cleaned = stripFences(text);
  const candidates = [cleaned, cleaned.match(/\{[\s\S]*\}/)?.[0]].filter(
    (value): value is string => Boolean(value),
  );
  for (const candidate of candidates) {
    try {
      const parsed: unknown = JSON.parse(candidate);
      if (isRecord(parsed)) return parsed;
    } catch {
      // Try the next bounded representation.
    }
  }
  return null;
}

function sanitizeFilter(value: Record<string, unknown> | null): FilterResponse {
  if (!value) return {};
  const result: FilterResponse = {};
  const qualities = new Set(["SD", "720p", "1080p", "4K"]);
  if (typeof value.minQuality === "string" && qualities.has(value.minQuality)) {
    result.minQuality = value.minQuality as FilterResponse["minQuality"];
  }
  if (typeof value.maxSizeGB === "number" && Number.isFinite(value.maxSizeGB) && value.maxSizeGB > 0 && value.maxSizeGB <= 1_000) {
    result.maxSizeGB = value.maxSizeGB;
  }
  for (const key of ["cachedOnly", "codecPreferred", "hdrOnly"] as const) {
    if (typeof value[key] === "boolean") result[key] = value[key];
  }
  if (typeof value.language === "string" && /^[A-Za-z]{2,3}$/.test(value.language)) {
    result.language = value.language.toUpperCase();
  }
  return result;
}

function sanitizeTroubleshoot(value: Record<string, unknown> | null): {
  cause: string;
  advice: string;
  suggestedAction: TroubleshootAction;
} {
  const fallback = {
    cause: "Something went wrong during playback.",
    advice: "Try a different stream or the other player.",
    suggestedAction: "chooseDifferentStream" as const,
  };
  if (!value) return fallback;
  const actions = new Set<TroubleshootAction>([
    "tryOtherEngine",
    "chooseDifferentStream",
    "checkSMB",
    "checkAddons",
    "none",
  ]);
  const action = typeof value.suggestedAction === "string" && actions.has(value.suggestedAction as TroubleshootAction)
    ? (value.suggestedAction as TroubleshootAction)
    : fallback.suggestedAction;
  return {
    cause: boundedString(value.cause, fallback.cause),
    advice: boundedString(value.advice, fallback.advice),
    suggestedAction: action,
  };
}

function boundedString(value: unknown, fallback: string): string {
  return typeof value === "string" && value.trim() ? value.trim().slice(0, 500) : fallback;
}

function stripFences(text: string): string {
  return text.replace(/```json/gi, "").replace(/```/g, "").trim();
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function responseHeaders(request: Request, env: Env, additional: HeadersInit = {}): Headers {
  const headers = new Headers({
    "Cache-Control": "no-store",
    "Content-Type": "application/json; charset=utf-8",
    "X-Content-Type-Options": "nosniff",
    "X-Nova-Worker": env.SERVICE_NAME || DEFAULT_SERVICE_NAME,
    ...additional,
  });
  const origin = request.headers.get("Origin");
  if (origin && env.ALLOWED_ORIGIN && origin === env.ALLOWED_ORIGIN) {
    headers.set("Access-Control-Allow-Origin", origin);
    headers.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    headers.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
    headers.set("Vary", "Origin");
  }
  return headers;
}

function json(
  value: unknown,
  status: number,
  request: Request,
  env: Env,
  additionalHeaders: HeadersInit = {},
): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: responseHeaders(request, env, additionalHeaders),
  });
}

function log(level: "info" | "error", message: string, fields: Record<string, unknown>): void {
  const entry = JSON.stringify({ level, message, timestamp: new Date().toISOString(), ...fields });
  if (level === "error") console.error(entry);
  else console.log(entry);
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
