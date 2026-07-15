import http from "node:http";
import path from "node:path";
import express from "express";
import { config, paths } from "./config";
import { db } from "./db";
import { channelsRouter } from "./routes/channels";
import { messagesRouter } from "./routes/messages";
import { blobsRouter } from "./routes/blobs";
import { healthRouter } from "./routes/health";
import { errorHandler } from "./middleware/errorHandler";
import { handleUpgrade } from "./ws/upgrade";
import { startHeartbeat, closeAll } from "./ws/hub";

const app = express();

app.get("/send/:code", (_req, res) => {
  res.sendFile(path.join(paths.staticDir, "send.html"));
});

app.use(express.static(paths.staticDir));

app.use(channelsRouter);
app.use(messagesRouter);
app.use(blobsRouter);
app.use(healthRouter);

app.use(errorHandler);

const server = http.createServer(app);
server.on("upgrade", (req, socket, head) => {
  handleUpgrade(req, socket, head);
});

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
