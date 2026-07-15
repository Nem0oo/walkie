import fs from "node:fs";
import path from "node:path";
import { paths } from "../config";

export function blobFilename(id: string): string {
  return `${id}.m4a`;
}

export function blobPath(channelCode: string, id: string): string {
  return path.join(paths.blobsDir, channelCode, blobFilename(id));
}

export function ensureChannelDir(channelCode: string): string {
  const dir = path.join(paths.blobsDir, channelCode);
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}
