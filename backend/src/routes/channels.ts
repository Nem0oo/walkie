import { Router } from "express";
import { createChannel, getChannelByCode, revokeChannel, type Channel } from "../repositories/channels";
import { channelExists } from "../middleware/channelExists";
import { requireOwner } from "../middleware/requireOwner";
import { rateLimit } from "../middleware/rateLimit";
import { hashToken, newChannelCode, newOwnerToken } from "../services/ids";
import { closeChannel } from "../ws/hub";

export const channelsRouter = Router();

// Anonymous and callable cross-site (a plain POST needs no CORS preflight), so cap it.
const createLimit = rateLimit({ windowMs: 60 * 60 * 1000, max: 10 });

channelsRouter.post("/channels", createLimit, (_req, res) => {
  const ownerToken = newOwnerToken();
  let channel: Channel | undefined;
  // Astronomically unlikely to collide at this alphabet/length, but a channel code is a
  // primary key — retry a couple of times rather than 500ing on the rare clash.
  for (let attempt = 0; attempt < 5 && !channel; attempt++) {
    const code = newChannelCode();
    if (!getChannelByCode(code)) channel = createChannel(code, hashToken(ownerToken));
  }
  if (!channel) {
    res.status(500).json({ error: "could_not_allocate_code" });
    return;
  }
  // The only time the owner token is ever sent: the app stores it, the server keeps a hash.
  res.status(201).json({ code: channel.code, owner_token: ownerToken });
});

// Public: the sender page only needs to know whether the link still works.
channelsRouter.get("/channels/:code", channelExists, (_req, res) => {
  res.json(res.locals.channel);
});

// Invalidates the current link — cuts off everyone who has it. Owner-only: a sender
// holding the link must not be able to cut the owner's channel. Doesn't return a
// replacement code: the caller (the iOS app) re-runs its normal pairing flow to get a
// fresh one, rather than this endpoint duplicating that logic.
channelsRouter.post("/channels/:code/revoke", channelExists, requireOwner, (req, res) => {
  revokeChannel(req.params.code);
  closeChannel(req.params.code);
  res.status(204).send();
});
