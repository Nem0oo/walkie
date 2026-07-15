import type { NextFunction, Request, Response } from "express";
import { getChannelByCode } from "../repositories/channels";

// Used on every /channels/:code/* route so bad links 404 cheaply, before touching
// multer or ffmpeg.
export function channelExists(req: Request, res: Response, next: NextFunction): void {
  const channel = getChannelByCode(req.params.code);
  if (!channel) {
    res.status(404).json({ error: "channel_not_found" });
    return;
  }
  res.locals.channel = channel;
  next();
}
