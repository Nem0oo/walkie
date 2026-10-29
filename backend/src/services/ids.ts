import crypto from "node:crypto";
import { customAlphabet, nanoid } from "nanoid";
import { config } from "../config";

// Unambiguous alphabet (no 0/O, 1/I/L) — this code occasionally gets read aloud or
// retyped even though it's normally shared as a link.
const CHANNEL_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
const channelCode = customAlphabet(CHANNEL_ALPHABET, config.channelCodeLength);

export function newChannelCode(): string {
  return channelCode();
}

// Message IDs are never hand-typed (only ever appear in URLs/JSON), so the plain
// nanoid alphabet is fine.
export function newMessageId(): string {
  return nanoid(14);
}

// Owner tokens are only ever stored hashed — a leaked DB doesn't hand out owner access.
export function newOwnerToken(): string {
  return crypto.randomBytes(32).toString("base64url");
}

export function hashToken(token: string): string {
  return crypto.createHash("sha256").update(token).digest("hex");
}

export function matchesTokenHash(token: string, expectedHash: string): boolean {
  const actual = Buffer.from(hashToken(token), "hex");
  const expected = Buffer.from(expectedHash, "hex");
  return actual.length === expected.length && crypto.timingSafeEqual(actual, expected);
}
