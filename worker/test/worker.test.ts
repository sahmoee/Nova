import { SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";

describe("Nova Worker", () => {
  it("reports health without exposing secrets", async () => {
    const response = await SELF.fetch("https://example.com/health");
    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(response.headers.get("x-nova-worker")).toBe("nova-ai-worker");
    await expect(response.json()).resolves.toMatchObject({
      ok: true,
      service: "nova-ai-worker",
      product: "Nova",
    });
  });

  it("rejects non-JSON and oversized requests", async () => {
    const wrongType = await SELF.fetch("https://example.com/titles", {
      method: "POST",
      body: "hello",
      headers: { "content-type": "text/plain" },
    });
    expect(wrongType.status).toBe(415);

    const tooLarge = await SELF.fetch("https://example.com/titles", {
      method: "POST",
      body: "{}",
      headers: {
        "content-type": "application/json",
        "content-length": String(7 * 1024 * 1024),
      },
    });
    expect(tooLarge.status).toBe(413);
  });

  it("creates an encrypted share and consumes it exactly once", async () => {
    const create = await SELF.fetch("https://example.com/share/create", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ snapshot: "aGVsbG8=", contents: 3, enc: true, ttlDays: 1 }),
    });
    expect(create.status).toBe(200);
    const created = await create.json<{ code: string }>();
    expect(created.code).toMatch(/^[A-Z2-9]{8}$/);

    const fetchBody = JSON.stringify({ code: created.code });
    const first = await SELF.fetch("https://example.com/share/fetch", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: fetchBody,
    });
    expect(first.status).toBe(200);
    await expect(first.json()).resolves.toMatchObject({ snapshot: "aGVsbG8=", enc: true });

    const second = await SELF.fetch("https://example.com/share/fetch", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: fetchBody,
    });
    expect(second.status).toBe(404);
  });
});
