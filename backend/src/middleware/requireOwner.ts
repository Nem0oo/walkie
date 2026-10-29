import type { IncomingMessage } from "node:http";
import type { NextFunction, Request, Response } from "express";
import { getOwnerTokenHash } from "../repositories/channels";
import { matchesTokenHash } from "../services/ids";

/**
 * The channel code is shared with every sender, so it only grants sending. Reading the
 * history, downloading audio, subscribing and revoking also need the owner token, which
 * only the iOS app that created the channel holds (`Authorization: Bearer <token>`).
 */
export function isOwner(req: IncomingMessage, channelCode: string): boolean {
  const header = req.headers.authorization ?? "";
  const token = header.startsWith("Bearer ") ? header.slice("Bearer ".length).trim() : "";
  const hash = getOwnerTokenHash(channelCode);
  return Boolean(token && hash && matchesTokenHash(token, hash));
}

// Runs after `channelExists`, so an unknown/revoked channel still 404s first.
export function requireOwner(req: Request, res: Response, next: NextFunction): void {
  if (!isOwner(req, req.params.code)) {
    res.status(401).json({ error: "owner_token_required" });
    return;
  }
  next();
}
