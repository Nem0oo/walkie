import fs from "node:fs";
import { Router } from "express";
import { config } from "../config";
import { channelExists } from "../middleware/channelExists";
import { upload } from "../middleware/upload";
import { insertMessage, listMessagesSince, type MessageRow } from "../repositories/messages";
import { blobFilename, blobPath, ensureChannelDir } from "../services/storage";
import { newMessageId } from "../services/ids";
import { transcodeToM4a } from "../services/transcode";
import { broadcast } from "../ws/hub";

export const messagesRouter = Router();

function toDto(row: MessageRow) {
  return {
    id: row.id,
    url: `${config.publicBaseUrl}/channels/${row.channel_code}/blobs/${row.filename}`,
    sender: row.sender,
    created_at: row.created_at,
  };
}

messagesRouter.post("/channels/:code/messages", channelExists, upload.single("audio"), async (req, res, next) => {
  if (!req.file) {
    res.status(400).json({ error: "missing_audio" });
    return;
  }

  const code = req.params.code;
  const id = newMessageId();
  ensureChannelDir(code);
  const outputPath = blobPath(code, id);

  try {
    const { durationSeconds } = await transcodeToM4a(req.file.path, outputPath);
    const stat = fs.statSync(outputPath);

    const sender = (req.body.sender ?? "").toString().trim().slice(0, 40) || "Anonyme";

    const row = insertMessage({
      id,
      channelCode: code,
      filename: blobFilename(id),
      sizeBytes: stat.size,
      durationSeconds,
      sender,
    });

    const dto = toDto(row);
    broadcast(code, { type: "new_message", ...dto });
    res.status(201).json(dto);
  } catch (err) {
    next(err);
  } finally {
    fs.rm(req.file.path, { force: true }, () => {});
  }
});

messagesRouter.get("/channels/:code/messages", channelExists, (req, res) => {
  const since = typeof req.query.since === "string" ? req.query.since : undefined;
  const rows = listMessagesSince(req.params.code, since);
  res.json(rows.map(toDto));
});
