import type { NextFunction, Request, Response } from "express";
import { getActiveChannelByCode } from "../repositories/channels";

// Used on every /channels/:code/* route so bad links 404 cheaply, before touching
// multer or ffmpeg. A revoked channel 404s exactly like an unknown one — that's the
// whole point of revocation, the old link just stops working.
export function channelExists(req: Request, res: Response, next: NextFunction): void {
  const channel = getActiveChannelByCode(req.params.code);
  if (!channel) {
    res.status(404).json({ error: "channel_not_found" });
    return;
  }
  res.locals.channel = channel;
  next();
}
