import path from "node:path";

function int(name: string, fallback: number): number {
  const raw = process.env[name];
  if (!raw) return fallback;
  const n = Number.parseInt(raw, 10);
  if (!Number.isFinite(n) || n <= 0) {
    console.error(`Invalid ${name}: "${raw}" (expected a positive integer)`);
    process.exit(1);
  }
  return n;
}

export const config = {
  port: int("PORT", 3000),
  dataDir: path.resolve(process.env.DATA_DIR ?? "/data"),
  maxUploadBytes: int("MAX_UPLOAD_BYTES", 8 * 1024 * 1024),
  channelCodeLength: int("CHANNEL_CODE_LENGTH", 10),
  publicBaseUrl: (process.env.PUBLIC_BASE_URL ?? "http://localhost:3000").replace(/\/+$/, ""),
};

export const paths = {
  dbFile: path.join(config.dataDir, "db", "walkie.db"),
  blobsDir: path.join(config.dataDir, "blobs"),
  tmpDir: path.join(config.dataDir, "tmp"),
  staticDir: path.join(__dirname, "static"),
};
