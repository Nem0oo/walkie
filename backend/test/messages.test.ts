import "./setup";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { after, before, test } from "node:test";
import ffprobeStatic from "ffprobe-static";
import { bearer, createChannel, makeAudio, startServer, uploadAudio } from "./helpers";

let base: string;
let stop: () => void;
let tmp: string;
let oneSecond: string;

before(async () => {
  ({ base, stop } = await startServer());
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "walkie-audio-"));
  oneSecond = makeAudio(tmp, 1);
});
after(() => stop());

async function send(code: string): Promise<string> {
  const res = await uploadAudio(base, code, oneSecond);
  assert.equal(res.status, 201);
  return ((await res.json()) as { id: string }).id;
}

async function history(code: string, token: string, since?: string): Promise<string[]> {
  const query = since === undefined ? "" : `?since=${encodeURIComponent(since)}`;
  const res = await fetch(`${base}/channels/${code}/messages${query}`, { headers: bearer(token) });
  assert.equal(res.status, 200);
  return ((await res.json()) as Array<{ id: string }>).map((m) => m.id);
}

test("catch-up without a cursor returns the whole channel history, oldest first", async () => {
  const { code, owner_token } = await createChannel(base);
  const a = await send(code);
  const b = await send(code);
  const c = await send(code);

  assert.deepEqual(await history(code, owner_token), [a, b, c]);
});

test("catch-up with a cursor returns only what came after it", async () => {
  const { code, owner_token } = await createChannel(base);
  const a = await send(code);
  const b = await send(code);
  const c = await send(code);

  assert.deepEqual(await history(code, owner_token, a), [b, c]);
  assert.deepEqual(await history(code, owner_token, c), []);
});

test("catch-up never returns another channel's messages, even with that channel's id as cursor", async () => {
  const mine = await createChannel(base);
  const other = await createChannel(base);
  const theirs = await send(other.code);
  await send(mine.code);

  assert.deepEqual(await history(mine.code, mine.owner_token, theirs), []);
  assert.deepEqual(await history(mine.code, mine.owner_token, "unknown-id"), []);
});

test("a message's url points at the configured public base and the stored blob", async () => {
  const { code } = await createChannel(base);

  const res = await uploadAudio(base, code, oneSecond);
  const body = (await res.json()) as { id: string; url: string };

  assert.equal(body.url, `http://walkie.test/channels/${code}/blobs/${body.id}.m4a`);
});

test("audio longer than MAX_DURATION_SECONDS (3s in tests) is cut server-side", async () => {
  const { code, owner_token } = await createChannel(base);

  const res = await uploadAudio(base, code, makeAudio(tmp, 8));
  assert.equal(res.status, 201);
  const { url } = (await res.json()) as { url: string };
  const blob = await fetch(url.replace("http://walkie.test", base), { headers: bearer(owner_token) });
  const file = path.join(tmp, "stored.m4a");
  fs.writeFileSync(file, Buffer.from(await blob.arrayBuffer()));

  const duration = Number(
    execFileSync(ffprobeStatic.path, ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", file]).toString()
  );
  assert.ok(duration > 2.5 && duration <= 3.1, `stored duration was ${duration}s`);
});

test("an upload that isn't decodable audio is rejected with 422 and nothing is stored", async () => {
  const { code, owner_token } = await createChannel(base);
  const garbage = path.join(tmp, "garbage.ogg");
  fs.writeFileSync(garbage, "definitely not audio");

  const res = await uploadAudio(base, code, garbage);

  assert.equal(res.status, 422);
  assert.deepEqual(await history(code, owner_token), []);
});

test("an upload without an audio file is rejected with 400", async () => {
  const { code } = await createChannel(base);
  const form = new FormData();
  form.append("sender", "Test");

  const res = await fetch(`${base}/channels/${code}/messages`, { method: "POST", body: form });

  assert.equal(res.status, 400);
});
