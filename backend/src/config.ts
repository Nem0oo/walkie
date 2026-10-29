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

function intOrZero(name: string, fallback: number): number {
  return process.env[name] === "0" ? 0 : int(name, fallback);
}

function list(name: string): string[] {
  return (process.env[name] ?? "")
    .split(",")
    .map((v) => v.trim().replace(/\/+$/, ""))
    .filter(Boolean);
}

export const config = {
  port: int("PORT", 3000),
  dataDir: path.resolve(process.env.DATA_DIR ?? "/data"),
  maxUploadBytes: int("MAX_UPLOAD_BYTES", 8 * 1024 * 1024),
  channelCodeLength: int("CHANNEL_CODE_LENGTH", 10),
  // Server-side cap on a message's length (the web page stops at 120s on its own).
  maxDurationSeconds: int("MAX_DURATION_SECONDS", 125),
  // Number of reverse proxies in front of the app (nginx-proxy = 1), so rate limiting
  // sees the real client IP from X-Forwarded-For. 0 if the app is exposed directly.
  trustProxy: intOrZero("TRUST_PROXY", 1),
  // Comma-separated browser origins allowed to call the API cross-origin (e.g. another
  // site embedding the sender page). Empty by default: same-origin only.
  allowedOrigins: new Set(list("ALLOWED_ORIGINS")),
  publicBaseUrl: (process.env.PUBLIC_BASE_URL ?? "http://localhost:3000").replace(/\/+$/, ""),
};

export const paths = {
  dbFile: path.join(config.dataDir, "db", "walkie.db"),
  blobsDir: path.join(config.dataDir, "blobs"),
  tmpDir: path.join(config.dataDir, "tmp"),
  staticDir: path.join(__dirname, "static"),
};
