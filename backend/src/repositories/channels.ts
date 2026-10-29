import { db } from "../db";

export interface Channel {
  code: string;
  created_at: string;
  revoked_at: string | null;
}

export function createChannel(code: string, ownerTokenHash: string): Channel {
  db.prepare("INSERT INTO channels (code, owner_token_hash) VALUES (?, ?)").run(code, ownerTokenHash);
  return getChannelByCode(code)!;
}

/** Raw lookup, includes revoked channels — only for the code-collision check on creation. */
export function getChannelByCode(code: string): Channel | undefined {
  return db.prepare<[string], Channel>("SELECT code, created_at, revoked_at FROM channels WHERE code = ?").get(code);
}

/** What every client-facing route should use: a revoked channel behaves as if it doesn't exist. */
export function getActiveChannelByCode(code: string): Channel | undefined {
  return db
    .prepare<[string], Channel>("SELECT code, created_at, revoked_at FROM channels WHERE code = ? AND revoked_at IS NULL")
    .get(code);
}

/** Kept out of `Channel` so it can never end up in a JSON response by accident. */
export function getOwnerTokenHash(code: string): string | null {
  const row = db
    .prepare<[string], { owner_token_hash: string | null }>("SELECT owner_token_hash FROM channels WHERE code = ?")
    .get(code);
  return row?.owner_token_hash ?? null;
}

export function revokeChannel(code: string): void {
  db.prepare("UPDATE channels SET revoked_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE code = ?").run(code);
}
