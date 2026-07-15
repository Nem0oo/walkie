import { db } from "../db";

export interface MessageRow {
  seq: number;
  id: string;
  channel_code: string;
  filename: string;
  size_bytes: number;
  duration_seconds: number | null;
  sender: string;
  created_at: string;
}

export interface InsertMessageInput {
  id: string;
  channelCode: string;
  filename: string;
  sizeBytes: number;
  durationSeconds: number | null;
  sender: string;
}

export function insertMessage(input: InsertMessageInput): MessageRow {
  db.prepare(
    `INSERT INTO messages (id, channel_code, filename, size_bytes, duration_seconds, sender)
     VALUES (@id, @channelCode, @filename, @sizeBytes, @durationSeconds, @sender)`
  ).run(input);
  return getMessageById(input.id)!;
}

export function getMessageById(id: string): MessageRow | undefined {
  return db.prepare<[string], MessageRow>("SELECT * FROM messages WHERE id = ?").get(id);
}

/**
 * Catch-up query for the iOS REST fallback. `sinceId` unresolved (unknown/garbage)
 * returns [] rather than guessing at a fallback window.
 */
export function listMessagesSince(channelCode: string, sinceId: string | undefined): MessageRow[] {
  if (!sinceId) return [];

  const cursor = db
    .prepare<[string, string], { seq: number }>("SELECT seq FROM messages WHERE id = ? AND channel_code = ?")
    .get(sinceId, channelCode);
  if (!cursor) return [];

  return db
    .prepare<[string, number], MessageRow>(
      "SELECT * FROM messages WHERE channel_code = ? AND seq > ? ORDER BY seq ASC"
    )
    .all(channelCode, cursor.seq);
}
