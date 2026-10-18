-- database/migrations/002_payment_void.sql
-- Payments voided by the owner (wrong method, wrong amount, wrong order).
-- No DELETE: the row stays with who voided it, when and why; totals, cash count and exports skip it.
-- Additive only: the previous app version keeps working against this schema.
-- Idempotent: MySQL 8.4 has no ADD COLUMN IF NOT EXISTS, so the ALTER only runs when the column is missing.

SET @has_void := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'payments' AND COLUMN_NAME = 'voided_at'
);
SET @ddl := IF(@has_void = 0,
  'ALTER TABLE payments
     ADD COLUMN voided_at   DATETIME     NULL,
     ADD COLUMN voided_by   INT UNSIGNED NULL,
     ADD COLUMN void_reason VARCHAR(150) NULL,
     ADD CONSTRAINT fk_payments_voided_by FOREIGN KEY (voided_by) REFERENCES users (id),
     ADD CONSTRAINT chk_payments_void CHECK (
       (voided_at IS NULL AND voided_by IS NULL AND void_reason IS NULL) OR
       (voided_at IS NOT NULL AND voided_by IS NOT NULL AND void_reason IS NOT NULL)
     )',
  'DO 0');
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
