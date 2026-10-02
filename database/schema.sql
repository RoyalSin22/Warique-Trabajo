-- database/schema.sql
-- Warique Order System - MySQL 8.0.16+ (CHECK constraints are enforced from 8.0.16)

CREATE DATABASE IF NOT EXISTS warique_orders
  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE warique_orders;

-- ---------------------------------------------------------------------------
-- Users & roles
-- ---------------------------------------------------------------------------
CREATE TABLE users (
  id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  full_name     VARCHAR(100) NOT NULL,
  username      VARCHAR(50)  NOT NULL,
  password_hash VARCHAR(255) NOT NULL,                 -- bcrypt/argon2, never plain text
  role          ENUM('OWNER', 'WAITER', 'KITCHEN') NOT NULL,
  is_active     BOOLEAN  NOT NULL DEFAULT TRUE,
  created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT uq_users_username UNIQUE (username)
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------------
-- Menu
-- ---------------------------------------------------------------------------
CREATE TABLE categories (
  id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  name       VARCHAR(60) NOT NULL,
  sort_order SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  is_active  BOOLEAN NOT NULL DEFAULT TRUE,
  CONSTRAINT uq_categories_name UNIQUE (name)
) ENGINE = InnoDB;

CREATE TABLE dishes (
  id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  category_id  INT UNSIGNED  NOT NULL,
  name         VARCHAR(100)  NOT NULL,
  description  VARCHAR(255)  NULL,
  price        DECIMAL(10,2) NOT NULL,
  is_available BOOLEAN  NOT NULL DEFAULT TRUE,          -- "agotado" for the day
  is_active    BOOLEAN  NOT NULL DEFAULT TRUE,          -- soft delete (keeps history)
  created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_dishes_category FOREIGN KEY (category_id) REFERENCES categories (id),
  CONSTRAINT uq_dishes_category_name UNIQUE (category_id, name),
  CONSTRAINT chk_dishes_price CHECK (price >= 0)
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------------
-- Tables (mesas)
-- ---------------------------------------------------------------------------
CREATE TABLE dining_tables (
  id        INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  label     VARCHAR(20) NOT NULL,                       -- "Mesa 1", "Barra"
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  CONSTRAINT uq_dining_tables_label UNIQUE (label)
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------------
-- Orders
-- ---------------------------------------------------------------------------
CREATE TABLE orders (
  id             INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  order_type     ENUM('DINE_IN', 'TAKEAWAY') NOT NULL,
  table_id       INT UNSIGNED  NULL,
  customer_name  VARCHAR(80)   NULL,                    -- optional, useful for takeaway
  waiter_id      INT UNSIGNED  NOT NULL,
  status         ENUM('PENDING', 'IN_PREPARATION', 'READY', 'DELIVERED', 'CANCELLED')
                 NOT NULL DEFAULT 'PENDING',
  payment_status ENUM('UNPAID', 'PARTIAL', 'PAID') NOT NULL DEFAULT 'UNPAID',
  total          DECIMAL(10,2) NOT NULL DEFAULT 0,      -- maintained by the service layer
  notes          VARCHAR(255)  NULL,
  cancel_reason  VARCHAR(255)  NULL,
  created_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  paid_at        DATETIME NULL,
  CONSTRAINT fk_orders_table  FOREIGN KEY (table_id)  REFERENCES dining_tables (id),
  CONSTRAINT fk_orders_waiter FOREIGN KEY (waiter_id) REFERENCES users (id),
  CONSTRAINT chk_orders_type_table CHECK (
    (order_type = 'DINE_IN'  AND table_id IS NOT NULL) OR
    (order_type = 'TAKEAWAY' AND table_id IS NULL)
  ),
  CONSTRAINT chk_orders_total  CHECK (total >= 0),
  CONSTRAINT chk_orders_cancel CHECK (status <> 'CANCELLED' OR cancel_reason IS NOT NULL),
  INDEX idx_orders_status_created  (status, created_at),          -- kitchen pending list
  INDEX idx_orders_payment_created (payment_status, created_at),  -- unpaid orders
  INDEX idx_orders_created         (created_at)                   -- daily reports
) ENGINE = InnoDB;

CREATE TABLE order_items (
  id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  order_id   INT UNSIGNED      NOT NULL,
  dish_id    INT UNSIGNED      NOT NULL,
  dish_name  VARCHAR(100)      NOT NULL,                -- snapshot at order time
  unit_price DECIMAL(10,2)     NOT NULL,                -- snapshot at order time
  quantity   SMALLINT UNSIGNED NOT NULL,
  subtotal   DECIMAL(12,2) AS (unit_price * quantity) STORED,
  notes      VARCHAR(150)      NULL,                    -- "sin ají", "poco arroz"
  CONSTRAINT fk_order_items_order FOREIGN KEY (order_id) REFERENCES orders (id),
  CONSTRAINT fk_order_items_dish  FOREIGN KEY (dish_id)  REFERENCES dishes (id),
  CONSTRAINT chk_order_items_qty   CHECK (quantity > 0),
  CONSTRAINT chk_order_items_price CHECK (unit_price >= 0)
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------------
-- Payments (1..n per order: allows split cash + Yape)
-- ---------------------------------------------------------------------------
CREATE TABLE payments (
  id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  order_id         INT UNSIGNED  NOT NULL,
  method           ENUM('CASH', 'YAPE', 'PLIN') NOT NULL,
  amount           DECIMAL(10,2) NOT NULL,
  amount_received  DECIMAL(10,2) NULL,                  -- cash only
  change_given     DECIMAL(10,2) AS (
                     CASE WHEN method = 'CASH' THEN amount_received - amount END
                   ) STORED,
  operation_number VARCHAR(30)   NULL,                  -- Yape/Plin reference (recommended)
  registered_by    INT UNSIGNED  NOT NULL,
  created_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_payments_order FOREIGN KEY (order_id)      REFERENCES orders (id),
  CONSTRAINT fk_payments_user  FOREIGN KEY (registered_by) REFERENCES users (id),
  CONSTRAINT chk_payments_amount CHECK (amount > 0),
  CONSTRAINT chk_payments_method CHECK (
    (method = 'CASH' AND amount_received IS NOT NULL
                     AND amount_received >= amount
                     AND operation_number IS NULL) OR
    (method IN ('YAPE', 'PLIN') AND amount_received IS NULL)
  ),
  INDEX idx_payments_created (created_at)
) ENGINE = InnoDB;
