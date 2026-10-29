-- SHA-256 of the owner token handed to the iOS app at channel creation. NULL for
-- channels created before this migration: they have no owner, so every owner-only
-- route rejects them and the app re-pairs onto a fresh channel.
ALTER TABLE channels ADD COLUMN owner_token_hash TEXT;
