import http from "node:http";
import path from "node:path";
import express from "express";
import { config, paths } from "./config";
import { channelsRouter } from "./routes/channels";
import { messagesRouter } from "./routes/messages";
import { blobsRouter } from "./routes/blobs";
import { healthRouter } from "./routes/health";
import { errorHandler } from "./middleware/errorHandler";
import { handleUpgrade } from "./ws/upgrade";

// Builds the HTTP + WebSocket server without listening — index.ts runs it, the tests
// start their own on a random port.
export function createServer(): http.Server {
  const app = express();
  app.set("trust proxy", config.trustProxy);

  // CORS minimal (pas de dépendance "cors") : seules les origines listées dans
  // ALLOWED_ORIGINS peuvent appeler ces endpoints depuis un navigateur. L'autorisation
  // reste le code de channel et le jeton propriétaire (cf. requireOwner.ts) — ceci ne fait
  // qu'autoriser le navigateur à lire la réponse pour ces origines précises.
  app.use((req, res, next) => {
    const origin = req.headers.origin;
    if (origin && config.allowedOrigins.has(origin)) {
      res.setHeader("Access-Control-Allow-Origin", origin);
      res.setHeader("Vary", "Origin");
    }
    next();
  });

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
    // An exception escaping this listener would take the whole process down — and the
    // upgrade request is fully attacker-controlled.
    try {
      handleUpgrade(req, socket, head);
    } catch (err) {
      console.error("[ws] upgrade failed:", err instanceof Error ? err.message : err);
      socket.destroy();
    }
  });
  return server;
}
