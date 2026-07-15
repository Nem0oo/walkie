import { WebSocket } from "ws";

interface TrackedSocket extends WebSocket {
  isAlive?: boolean;
}

const subscribers = new Map<string, Set<TrackedSocket>>();

export function subscribe(channelCode: string, ws: TrackedSocket): void {
  if (!subscribers.has(channelCode)) subscribers.set(channelCode, new Set());
  subscribers.get(channelCode)!.add(ws);

  ws.isAlive = true;
  ws.on("pong", () => {
    ws.isAlive = true;
  });
  ws.on("close", () => {
    subscribers.get(channelCode)?.delete(ws);
  });
}

export function closeAll(): void {
  for (const sockets of subscribers.values()) {
    for (const ws of sockets) ws.close();
  }
}

export function broadcast(channelCode: string, payload: unknown): void {
  const sockets = subscribers.get(channelCode);
  if (!sockets || sockets.size === 0) return;

  const json = JSON.stringify(payload);
  for (const ws of sockets) {
    if (ws.readyState === WebSocket.OPEN) ws.send(json);
  }
}

// nginx-proxy's default proxy_read_timeout is 60s (confirmed: no override in this
// host's config), so idle WS connections get killed by the proxy at 60s of silence.
// Pinging at 25s keeps every connection's idle clock reset well under that ceiling
// from the server's side. The iOS client independently self-pings too (see
// WebSocketClient.swift) since URLSessionWebSocketTask never surfaces inbound
// ping/pong to the app layer — both heartbeats are needed, each covers one direction.
export function startHeartbeat(intervalMs = 25_000): NodeJS.Timeout {
  return setInterval(() => {
    for (const sockets of subscribers.values()) {
      for (const ws of sockets) {
        if (ws.isAlive === false) {
          ws.terminate();
          continue;
        }
        ws.isAlive = false;
        ws.ping();
      }
    }
  }, intervalMs);
}
