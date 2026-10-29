import type { IncomingMessage } from "node:http";
import type { Duplex } from "node:stream";
import { WebSocketServer } from "ws";
import { getActiveChannelByCode } from "../repositories/channels";
import { isOwner } from "../middleware/requireOwner";
import { subscribe } from "./hub";

const SUBSCRIBE_PATH = /^\/channels\/([^/]+)\/subscribe$/;

// Clients never send anything but pings — no reason to accept the 100 MiB default.
const wss = new WebSocketServer({ noServer: true, maxPayload: 1024 });

function reject(socket: Duplex, status: string): void {
  socket.end(`HTTP/1.1 ${status}\r\nConnection: close\r\nContent-Length: 0\r\n\r\n`);
}

export function handleUpgrade(req: IncomingMessage, socket: Duplex, head: Buffer): void {
  const url = new URL(req.url ?? "", "http://internal");
  const match = url.pathname.match(SUBSCRIBE_PATH);

  if (!match) {
    console.log("[ws] upgrade rejected, no path match");
    socket.destroy();
    return;
  }

  let channelCode: string;
  try {
    channelCode = decodeURIComponent(match[1]);
  } catch {
    reject(socket, "400 Bad Request"); // malformed %-escape
    return;
  }

  // Same statuses as the REST routes: the iOS app reads 404/401 here as "this channel
  // is gone for me" and re-pairs instead of retrying forever.
  if (!getActiveChannelByCode(channelCode)) {
    console.log("[ws] upgrade rejected, unknown channel");
    reject(socket, "404 Not Found");
    return;
  }
  if (!isOwner(req, channelCode)) {
    console.log("[ws] upgrade rejected, missing or wrong owner token");
    reject(socket, "401 Unauthorized");
    return;
  }

  wss.handleUpgrade(req, socket, head, (ws) => {
    subscribe(channelCode, ws);
  });
}
