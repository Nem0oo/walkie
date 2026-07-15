import fs from "node:fs";
import multer from "multer";
import { config, paths } from "../config";

fs.mkdirSync(paths.tmpDir, { recursive: true });

// Disk storage, not memory: ffmpeg needs a real input file path anyway, and this keeps
// multi-megabyte uploads off the Node heap.
export const upload = multer({
  storage: multer.diskStorage({ destination: paths.tmpDir }),
  limits: { fileSize: config.maxUploadBytes, files: 1 },
  fileFilter: (_req, file, cb) => {
    cb(null, file.mimetype.startsWith("audio/"));
  },
});
