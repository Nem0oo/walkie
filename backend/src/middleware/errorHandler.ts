import type { NextFunction, Request, Response } from "express";
import multer from "multer";
import { TranscodeError } from "../services/transcode";

export function errorHandler(err: unknown, _req: Request, res: Response, _next: NextFunction): void {
  if (err instanceof multer.MulterError) {
    if (err.code === "LIMIT_FILE_SIZE") {
      res.status(413).json({ error: "file_too_large" });
      return;
    }
    res.status(400).json({ error: "upload_error" });
    return;
  }

  if (err instanceof TranscodeError) {
    res.status(422).json({ error: "unsupported_audio" });
    return;
  }

  console.error(err);
  res.status(500).json({ error: "internal_error" });
}
