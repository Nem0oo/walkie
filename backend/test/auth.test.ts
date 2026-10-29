import "./setup";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { after, before, test } from "node:test";
import { bearer, createChannel, makeAudio, startServer, uploadAudio, wsHandshake } from "./helpers";

// The channel code is shared with every sender: it must only allow sending. Everything
// else (history, audio, live subscription, revocation) needs the owner token.

let base: string;
let stop: () => void;
let audioFile: string;

before(async () => {
  ({ base, stop } = await startServer());
  audioFile = makeAudio(fs.mkdtempSync(path.join(os.tmpdir(), "walkie-audio-")), 1);
});
after(() => stop());

test("creating a channel hands out an owner token that the public channel lookup never exposes", async () => {
  const { code, owner_token } = await createChannel(base);
  assert.match(owner_token, /^[A-Za-z0-9_-]{40,}$/);

  const res = await fetch(`${base}/channels/${code}`);
  assert.equal(res.status, 200);
  const body = await res.text();
  assert.deepEqual(Object.keys(JSON.parse(body)).sort(), ["code", "created_at", "revoked_at"]);
  assert.ok(!body.includes(owner_token));
});

test("a sender without the owner token can still send a message", async () => {
  const { code } = await createChannel(base);

  const res = await uploadAudio(base, code, audioFile);

  assert.equal(res.status, 201);
});

test("reading the message history requires this channel's owner token", async () => {
  const mine = await createChannel(base);
  const other = await createChannel(base);
  const url = `${base}/channels/${mine.code}/messages`;

  assert.equal((await fetch(url)).status, 401);
  assert.equal((await fetch(url, { headers: bearer("not-the-token") })).status, 401);
  assert.equal((await fetch(url, { headers: bearer(other.owner_token) })).status, 401);
  assert.equal((await fetch(url, { headers: bearer(mine.owner_token) })).status, 200);
});

test("downloading a message's audio requires the owner token", async () => {
  const { code, owner_token } = await createChannel(base);
  const message = (await (await uploadAudio(base, code, audioFile)).json()) as { url: string };
  const blobUrl = message.url.replace("http://walkie.test", base);

  assert.equal((await fetch(blobUrl)).status, 401);
  const res = await fetch(blobUrl, { headers: bearer(owner_token) });
  assert.equal(res.status, 200);
  assert.equal(res.headers.get("content-type"), "audio/mp4");
});

test("subscribing to live messages requires the owner token", async () => {
  const { code, owner_token } = await createChannel(base);
  const wsUrl = `${base.replace("http", "ws")}/channels/${code}/subscribe`;

  assert.equal((await wsHandshake(wsUrl)).status, 401);
  assert.equal((await wsHandshake(wsUrl, bearer("not-the-token"))).status, 401);
  assert.equal((await wsHandshake(`${base.replace("http", "ws")}/channels/NOPE/subscribe`, bearer(owner_token))).status, 404);
  const ok = await wsHandshake(wsUrl, bearer(owner_token));
  assert.equal(ok.status, "open");
  ok.ws!.close();
});

test("the owner's subscription receives a message sent by someone holding only the link", async () => {
  const { code, owner_token } = await createChannel(base);
  const { ws } = await wsHandshake(`${base.replace("http", "ws")}/channels/${code}/subscribe`, bearer(owner_token));
  const received = new Promise<{ type: string; id: string }>((resolve) => ws!.once("message", (data) => resolve(JSON.parse(data.toString()))));

  const sent = (await (await uploadAudio(base, code, audioFile)).json()) as { id: string };

  const push = await received;
  assert.equal(push.type, "new_message");
  assert.equal(push.id, sent.id);
  ws!.close();
});

test("only the owner can revoke, and a revoked channel then answers 404 everywhere", async () => {
  const { code, owner_token } = await createChannel(base);
  const revoke = (headers: Record<string, string> = {}) => fetch(`${base}/channels/${code}/revoke`, { method: "POST", headers });

  assert.equal((await revoke()).status, 401);
  assert.equal((await fetch(`${base}/channels/${code}`)).status, 200, "a refused revoke must leave the channel working");

  assert.equal((await revoke(bearer(owner_token))).status, 204);

  assert.equal((await fetch(`${base}/channels/${code}`)).status, 404);
  assert.equal((await fetch(`${base}/channels/${code}/messages`, { headers: bearer(owner_token) })).status, 404);
  assert.equal((await uploadAudio(base, code, audioFile)).status, 404);
  assert.equal((await wsHandshake(`${base.replace("http", "ws")}/channels/${code}/subscribe`, bearer(owner_token))).status, 404);
  assert.equal((await revoke(bearer(owner_token))).status, 404);
});
