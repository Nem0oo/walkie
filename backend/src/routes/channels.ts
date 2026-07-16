import { Router } from "express";
import { createChannel, getChannelByCode, revokeChannel, type Channel } from "../repositories/channels";
import { channelExists } from "../middleware/channelExists";
import { newChannelCode } from "../services/ids";
import { closeChannel } from "../ws/hub";

export const channelsRouter = Router();

channelsRouter.post("/channels", (_req, res) => {
  let channel: Channel | undefined;
  // Astronomically unlikely to collide at this alphabet/length, but a channel code is a
  // primary key — retry a couple of times rather than 500ing on the rare clash.
  for (let attempt = 0; attempt < 5 && !channel; attempt++) {
    const code = newChannelCode();
    if (!getChannelByCode(code)) channel = createChannel(code);
  }
  if (!channel) {
    res.status(500).json({ error: "could_not_allocate_code" });
    return;
  }
  res.status(201).json({ code: channel.code });
});

channelsRouter.get("/channels/:code", channelExists, (_req, res) => {
  res.json(res.locals.channel);
});

// Invalidates the current link — the code itself is the only "secret" in this app, so
// this is the sole way to cut off everyone who has it. Knowing the current (still
// active) code is the only authorization needed, same trust model as everything else.
// Doesn't return a replacement code: the caller (the iOS app) re-runs its normal
// pairing flow to get a fresh one, rather than this endpoint duplicating that logic.
channelsRouter.post("/channels/:code/revoke", channelExists, (req, res) => {
  revokeChannel(req.params.code);
  closeChannel(req.params.code);
  res.status(204).send();
});
