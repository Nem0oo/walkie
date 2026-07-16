import type { IncomingMessage } from "node:http";
import type { Duplex } from "node:stream";
import { WebSocketServer } from "ws";
import { getActiveChannelByCode } from "../repositories/channels";
import { subscribe } from "./hub";

const SUBSCRIBE_PATH = /^\/channels\/([^/]+)\/subscribe$/;

const wss = new WebSocketServer({ noServer: true });

export function handleUpgrade(req: IncomingMessage, socket: Duplex, head: Buffer): void {
  const url = new URL(req.url ?? "", "http://internal");
  const match = url.pathname.match(SUBSCRIBE_PATH);

  if (!match) {
    console.log(`[ws] upgrade rejected, no path match: ${url.pathname}`);
    socket.destroy();
    return;
  }

  const channelCode = decodeURIComponent(match[1]);
  if (!getActiveChannelByCode(channelCode)) {
    console.log(`[ws] upgrade rejected, unknown channel: ${channelCode}`);
    socket.write("HTTP/1.1 404 Not Found\r\n\r\n");
    socket.destroy();
    return;
  }

  wss.handleUpgrade(req, socket, head, (ws) => {
    subscribe(channelCode, ws);
  });
}
