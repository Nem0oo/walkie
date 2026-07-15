import fs from "node:fs";
import { Router } from "express";
import { channelExists } from "../middleware/channelExists";
import { blobPath } from "../services/storage";

export const blobsRouter = Router();

// filename is attacker-controlled input from the URL — anchor the regex and reject
// anything else before it ever reaches the filesystem (path traversal guard).
const SAFE_FILENAME = /^[A-Za-z0-9_-]+\.m4a$/;

blobsRouter.get("/channels/:code/blobs/:filename", channelExists, (req, res) => {
  if (!SAFE_FILENAME.test(req.params.filename)) {
    res.status(400).json({ error: "invalid_filename" });
    return;
  }

  const filePath = blobPath(req.params.code, req.params.filename.replace(/\.m4a$/, ""));
  if (!fs.existsSync(filePath)) {
    res.status(404).json({ error: "blob_not_found" });
    return;
  }

  res.set("Content-Type", "audio/mp4");
  res.set("Cache-Control", "private, max-age=31536000, immutable");
  res.sendFile(filePath);
});
