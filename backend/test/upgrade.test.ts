import "./setup";
import assert from "node:assert/strict";
import net from "node:net";
import { after, test } from "node:test";
import { startServer } from "./helpers";

/** Sends a raw upgrade request (a WS client library would refuse to build a malformed path). */
function rawUpgrade(base: string, path: string): Promise<string> {
  const { hostname, port } = new URL(base);
  return new Promise((resolve, reject) => {
    const socket = net.connect(Number(port), hostname, () => {
      socket.write(
        `GET ${path} HTTP/1.1\r\nHost: ${hostname}\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n` +
          `Sec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n`
      );
    });
    let data = "";
    // A crashed handler never answers nor closes the socket — give up rather than hang.
    socket.setTimeout(2000, () => socket.destroy());
    socket.on("data", (chunk) => (data += chunk));
    socket.on("close", () => resolve(data));
    socket.on("error", reject);
  });
}

test("a malformed %-escape in the subscribe path gets a 400 and the server keeps running", async () => {
  const { base, stop } = await startServer();
  after(stop);

  const response = await rawUpgrade(base, "/channels/%ZZ/subscribe");

  assert.match(response, /^HTTP\/1\.1 400 /);
  const health = await fetch(`${base}/health`);
  assert.equal(health.status, 200);
});
