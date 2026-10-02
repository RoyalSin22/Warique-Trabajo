-- database/app-user.sql
-- Least-privilege MySQL user for the backend (no DELETE, no DDL).
-- Replace the password before running. Do NOT commit the real one.
CREATE USER IF NOT EXISTS 'warique_app'@'localhost' IDENTIFIED BY 'CHANGE_ME';
GRANT SELECT, INSERT, UPDATE ON warique_orders.* TO 'warique_app'@'localhost';
FLUSH PRIVILEGES;
