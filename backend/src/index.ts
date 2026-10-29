import { config } from "./config";
import { db } from "./db";
import { createServer } from "./app";
import { startHeartbeat, closeAll } from "./ws/hub";

const server = createServer();
const heartbeat = startHeartbeat();

server.listen(config.port, () => {
  console.log(`walkie backend listening on :${config.port}`);
});

function shutdown(signal: string): void {
  console.log(`${signal} received, shutting down`);
  clearInterval(heartbeat);
  // Close subscriber sockets first so server.close() isn't blocked waiting on
  // idle keep-alive connections.
  closeAll();
  server.close(() => {
    db.close();
    process.exit(0);
  });
}

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
