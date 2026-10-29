import type { NextFunction, Request, Response } from "express";

/**
 * Fixed-window, per-IP, in-memory limiter (single process, no dependency). Only the
 * anonymous, expensive endpoints use it: channel creation and uploads (each upload
 * spawns an ffmpeg). `req.ip` is the real client only because `trust proxy` is set
 * (see `config.trustProxy`) — behind nginx-proxy every request would otherwise share
 * the proxy's address.
 */
export function rateLimit(options: { windowMs: number; max: number }) {
  const hits = new Map<string, { count: number; resetAt: number }>();

  // Drop expired windows so the map can't grow with every IP ever seen.
  setInterval(() => {
    const now = Date.now();
    for (const [ip, entry] of hits) if (entry.resetAt <= now) hits.delete(ip);
  }, options.windowMs).unref();

  return (req: Request, res: Response, next: NextFunction): void => {
    const now = Date.now();
    const key = req.ip ?? "unknown";
    let entry = hits.get(key);
    if (!entry || entry.resetAt <= now) {
      entry = { count: 0, resetAt: now + options.windowMs };
      hits.set(key, entry);
    }
    entry.count++;
    if (entry.count > options.max) {
      res.setHeader("Retry-After", Math.ceil((entry.resetAt - now) / 1000).toString());
      res.status(429).json({ error: "rate_limited" });
      return;
    }
    next();
  };
}
