import "./setup";
import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import { startServer } from "./helpers";

let base: string;
let stop: () => void;

before(async () => {
  ({ base, stop } = await startServer());
});
after(() => stop());

function createFrom(ip: string): Promise<Response> {
  return fetch(`${base}/channels`, { method: "POST", headers: { "X-Forwarded-For": ip } });
}

test("one client can create 10 channels per hour, the 11th gets 429 with Retry-After", async () => {
  for (let i = 1; i <= 10; i++) assert.equal((await createFrom("203.0.113.1")).status, 201, `creation #${i}`);

  const res = await createFrom("203.0.113.1");

  assert.equal(res.status, 429);
  const retryAfter = Number(res.headers.get("retry-after"));
  assert.ok(retryAfter > 3500 && retryAfter <= 3600, `Retry-After was ${retryAfter}`);
});

test("the limit is per client IP as forwarded by the proxy, not shared by everyone", async () => {
  for (let i = 0; i < 11; i++) await createFrom("203.0.113.2");

  assert.equal((await createFrom("203.0.113.3")).status, 201);
});

test("one client can attempt 30 uploads per 10 minutes, the 31st gets 429 before any processing", async () => {
  const upload = () =>
    fetch(`${base}/channels/UNKNOWN/messages`, { method: "POST", headers: { "X-Forwarded-For": "203.0.113.4" } });
  // The limit applies even to doomed requests: it runs before the channel lookup.
  for (let i = 1; i <= 30; i++) assert.equal((await upload()).status, 404, `upload #${i}`);

  assert.equal((await upload()).status, 429);
});
