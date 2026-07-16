import { WebSocket } from "ws";

interface TrackedSocket extends WebSocket {
  isAlive?: boolean;
}

const subscribers = new Map<string, Set<TrackedSocket>>();

function log(message: string): void {
  console.log(`${new Date().toISOString()} ${message}`);
}

export function subscribe(channelCode: string, ws: TrackedSocket): void {
  if (!subscribers.has(channelCode)) subscribers.set(channelCode, new Set());
  subscribers.get(channelCode)!.add(ws);
  log(`[ws] subscribed channel=${channelCode} subscribers=${subscribers.get(channelCode)!.size}`);

  ws.isAlive = true;
  ws.on("pong", () => {
    log(`[ws] pong channel=${channelCode}`);
    ws.isAlive = true;
  });
  ws.on("close", (code, reason) => {
    subscribers.get(channelCode)?.delete(ws);
    log(`[ws] closed channel=${channelCode} code=${code} reason=${reason.toString() || "(none)"}`);
  });
  ws.on("error", (err) => {
    log(`[ws] error channel=${channelCode}: ${err.message}`);
  });
}

export function closeAll(): void {
  for (const sockets of subscribers.values()) {
    for (const ws of sockets) ws.close();
  }
}

export function broadcast(channelCode: string, payload: unknown): void {
  const sockets = subscribers.get(channelCode);
  log(`[ws] broadcast channel=${channelCode} subscribers=${sockets?.size ?? 0}`);
  if (!sockets || sockets.size === 0) return;

  const json = JSON.stringify(payload);
  for (const ws of sockets) {
    log(`[ws] send channel=${channelCode} readyState=${ws.readyState} bytes=${json.length}`);
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(json, (err) => {
        if (err) log(`[ws] send failed channel=${channelCode}: ${err.message}`);
      });
    }
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
    for (const [channelCode, sockets] of subscribers) {
      for (const ws of sockets) {
        if (ws.isAlive === false) {
          log(`[ws] terminating dead connection channel=${channelCode} (no pong since last ping)`);
          ws.terminate();
          continue;
        }
        ws.isAlive = false;
        log(`[ws] ping channel=${channelCode}`);
        ws.ping();
      }
    }
  }, intervalMs);
}
