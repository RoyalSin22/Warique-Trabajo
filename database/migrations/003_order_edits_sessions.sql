-- database/migrations/003_order_edits_sessions.sql
-- 1) Order lines added after the order was sent, and lines removed with a reason (never deleted:
--    the kitchen and the owner see what changed, and the app account has no DELETE right).
-- 2) users.token_version: changing or resetting a password invalidates every open session.
-- Additive only: the previous app version keeps working against this schema.
-- Idempotent: MySQL 8.4 has no ADD COLUMN IF NOT EXISTS, so each ALTER only runs when needed.

SET @has_item_cols := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'order_items' AND COLUMN_NAME = 'cancelled_at'
);
SET @ddl := IF(@has_item_cols = 0,
  'ALTER TABLE order_items
     ADD COLUMN added_at      DATETIME     NULL,   -- NULL = sent with the order; set = added later
     ADD COLUMN cancelled_at  DATETIME     NULL,
     ADD COLUMN cancelled_by  INT UNSIGNED NULL,
     ADD COLUMN cancel_reason VARCHAR(150) NULL,
     ADD CONSTRAINT fk_order_items_cancelled_by FOREIGN KEY (cancelled_by) REFERENCES users (id),
     ADD CONSTRAINT chk_order_items_cancel CHECK (
       (cancelled_at IS NULL AND cancelled_by IS NULL AND cancel_reason IS NULL) OR
       (cancelled_at IS NOT NULL AND cancelled_by IS NOT NULL AND cancel_reason IS NOT NULL)
     )',
  'DO 0');
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @has_token_version := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND COLUMN_NAME = 'token_version'
);
SET @ddl := IF(@has_token_version = 0,
  'ALTER TABLE users ADD COLUMN token_version INT UNSIGNED NOT NULL DEFAULT 0',
  'DO 0');
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
