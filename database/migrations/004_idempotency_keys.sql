-- database/migrations/004_idempotency_keys.sql
-- Retried requests (Idempotency-Key) survive a restart of the PC: the first response of a new
-- order or payment is kept 15 minutes, so a retry after a reboot returns it instead of a duplicate.
-- The app account has no DELETE: old responses are blanked with UPDATE (the row stays, ~100 bytes).
CREATE TABLE IF NOT EXISTS idempotency_keys (
  key_hash   CHAR(64)   NOT NULL PRIMARY KEY,     -- SHA-256 of user + method + URL + key
  response   MEDIUMTEXT NULL,                     -- JSON of the first response; NULL once expired
  created_at DATETIME   NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_idempotency_created (created_at)
) ENGINE = InnoDB;
