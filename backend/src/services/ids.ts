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
