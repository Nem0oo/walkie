import { Router } from "express";
import { createChannel, getChannelByCode, type Channel } from "../repositories/channels";
import { channelExists } from "../middleware/channelExists";
import { newChannelCode } from "../services/ids";

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
