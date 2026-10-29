import { execFileSync } from "node:child_process";
import type { AddressInfo } from "node:net";
import path from "node:path";
import ffmpegPath from "ffmpeg-static";
import { WebSocket } from "ws";
import { createServer } from "../src/app";

/** Real HTTP server on a random port. Call `stop` from the test file's `after` hook. */
export async function startServer(): Promise<{ base: string; stop: () => void }> {
  const server = createServer();
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  return {
    base: `http://127.0.0.1:${(server.address() as AddressInfo).port}`,
    stop: () => {
      server.closeAllConnections();
      server.close();
    },
  };
}

let nextIp = 1;
/** Each call gets its own client IP (via X-Forwarded-For) so per-IP rate limits don't leak between tests. */
export function freshIp(): string {
  return `10.0.${Math.floor(nextIp / 250)}.${(nextIp++ % 250) + 1}`;
}

export async function createChannel(base: string): Promise<{ code: string; owner_token: string }> {
  const res = await fetch(`${base}/channels`, { method: "POST", headers: { "X-Forwarded-For": freshIp() } });
  if (res.status !== 201) throw new Error(`createChannel: ${res.status}`);
  return res.json() as Promise<{ code: string; owner_token: string }>;
}

export function bearer(token: string): Record<string, string> {
  return { Authorization: `Bearer ${token}` };
}

/** A real Opus/Ogg file of `seconds` seconds — what a browser would upload. */
export function makeAudio(dir: string, seconds: number): string {
  const file = path.join(dir, `tone-${seconds}s.ogg`);
  execFileSync(ffmpegPath!, ["-loglevel", "error", "-y", "-f", "lavfi", "-i", `sine=f=440:d=${seconds}`, "-c:a", "libopus", "-b:a", "16k", file]);
  return file;
}

export async function uploadAudio(base: string, code: string, file: string, ip = freshIp()): Promise<Response> {
  const fs = await import("node:fs");
  const form = new FormData();
  form.append("audio", new Blob([fs.readFileSync(file)], { type: "audio/ogg" }), "recording.ogg");
  form.append("sender", "Test");
  return fetch(`${base}/channels/${code}/messages`, { method: "POST", body: form, headers: { "X-Forwarded-For": ip } });
}

/**
 * Result of a WebSocket handshake: "open" or the HTTP status the server refused it with
 * (0 if the connection was dropped without any response).
 */
export function wsHandshake(url: string, headers: Record<string, string> = {}): Promise<{ status: "open" | number; ws?: WebSocket }> {
  return new Promise((resolve) => {
    const ws = new WebSocket(url, { headers });
    ws.on("open", () => resolve({ status: "open", ws }));
    ws.on("unexpected-response", (_req, res) => resolve({ status: res.statusCode ?? 0 }));
    ws.on("error", () => resolve({ status: 0 }));
  });
}
