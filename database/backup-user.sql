-- database/backup-user.sql
-- Read-only MySQL user for the daily mysqldump (deploy/windows/backup.ps1).
-- install.ps1 runs this with a generated password; to run it by hand, replace CHANGE_ME first.
CREATE USER IF NOT EXISTS 'warique_backup'@'localhost' IDENTIFIED BY 'CHANGE_ME';
-- --single-transaction needs no LOCK TABLES; TRIGGER/SHOW VIEW let the dump include them
GRANT SELECT, SHOW VIEW, TRIGGER, LOCK TABLES ON warique_orders.* TO 'warique_backup'@'localhost';
FLUSH PRIVILEGES;
