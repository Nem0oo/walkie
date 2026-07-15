import { db } from "../db";

export interface Channel {
  code: string;
  created_at: string;
}

export function createChannel(code: string): Channel {
  db.prepare("INSERT INTO channels (code) VALUES (?)").run(code);
  return getChannelByCode(code)!;
}

export function getChannelByCode(code: string): Channel | undefined {
  return db.prepare<[string], Channel>("SELECT code, created_at FROM channels WHERE code = ?").get(code);
}
