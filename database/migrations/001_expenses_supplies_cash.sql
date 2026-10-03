-- database/migrations/001_expenses_supplies_cash.sql
-- Expenses, supplies with stock, and the daily cash count (arqueo).
-- Applied by deploy/windows/install.ps1 and update.ps1 (recorded in schema_migrations).
-- Additive only: the previous app version keeps working against this schema.
-- No USE: the runner selects the database configured at install time.

-- ---------------------------------------------------------------------------
-- Supplies (insumos) and their stock
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS supplies (
  id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  name       VARCHAR(60)  NOT NULL,
  unit       ENUM('KG', 'L', 'UNIDAD', 'ATADO', 'PAQUETE') NOT NULL,
  stock      DECIMAL(12,3) NOT NULL DEFAULT 0,       -- maintained by the service, one movement per change
  min_stock  DECIMAL(12,3) NOT NULL DEFAULT 0,       -- "stock bajo" alert threshold
  is_active  BOOLEAN NOT NULL DEFAULT TRUE,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT uq_supplies_name UNIQUE (name),
  CONSTRAINT chk_supplies_stock CHECK (stock >= 0),
  CONSTRAINT chk_supplies_min   CHECK (min_stock >= 0)
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------------
-- Expenses (gastos). A supply purchase is an expense with line items.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS expenses (
  id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  business_date DATE NOT NULL,                       -- local business day the expense belongs to
  category      ENUM('INSUMOS', 'GAS', 'SERVICIOS', 'SUELDOS', 'ALQUILER', 'TRANSPORTE', 'OTROS') NOT NULL,
  description   VARCHAR(150) NOT NULL,
  amount        DECIMAL(10,2) NOT NULL,
  paid_with     ENUM('CASH', 'OTHER') NOT NULL,      -- CASH comes out of the drawer (arqueo)
  is_void       BOOLEAN NOT NULL DEFAULT FALSE,      -- no DELETE: voided with a reason
  void_reason   VARCHAR(150) NULL,
  created_by    INT UNSIGNED NOT NULL,
  created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_expenses_user FOREIGN KEY (created_by) REFERENCES users (id),
  CONSTRAINT chk_expenses_amount CHECK (amount > 0),
  CONSTRAINT chk_expenses_void   CHECK (is_void = FALSE OR void_reason IS NOT NULL),
  INDEX idx_expenses_date (business_date)
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS expense_items (
  id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  expense_id INT UNSIGNED NOT NULL,
  supply_id  INT UNSIGNED NOT NULL,
  quantity   DECIMAL(12,3) NOT NULL,
  cost       DECIMAL(10,2) NOT NULL,                 -- line total paid
  CONSTRAINT fk_expense_items_expense FOREIGN KEY (expense_id) REFERENCES expenses (id),
  CONSTRAINT fk_expense_items_supply  FOREIGN KEY (supply_id)  REFERENCES supplies (id),
  CONSTRAINT chk_expense_items_qty  CHECK (quantity > 0),
  CONSTRAINT chk_expense_items_cost CHECK (cost >= 0)
) ENGINE = InnoDB;

-- Every stock change, with the resulting stock: the history explains every number on screen
CREATE TABLE IF NOT EXISTS supply_movements (
  id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  supply_id   INT UNSIGNED NOT NULL,
  type        ENUM('PURCHASE', 'COUNT', 'WASTE', 'USE', 'VOID') NOT NULL,
  quantity    DECIMAL(12,3) NOT NULL,                -- signed change (+ in, - out)
  stock_after DECIMAL(12,3) NOT NULL,
  expense_id  INT UNSIGNED NULL,
  note        VARCHAR(150) NULL,
  created_by  INT UNSIGNED NOT NULL,
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_movements_supply  FOREIGN KEY (supply_id)  REFERENCES supplies (id),
  CONSTRAINT fk_movements_expense FOREIGN KEY (expense_id) REFERENCES expenses (id),
  CONSTRAINT fk_movements_user    FOREIGN KEY (created_by) REFERENCES users (id),
  CONSTRAINT chk_movements_stock  CHECK (stock_after >= 0),
  INDEX idx_movements_supply (supply_id, created_at)
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------------
-- Cash count (arqueo): one session per business day
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS cash_sessions (
  id              INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  business_date   DATE NOT NULL,
  opening_amount  DECIMAL(10,2) NOT NULL,            -- change fund at opening
  opened_by       INT UNSIGNED NOT NULL,
  opened_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expected_amount DECIMAL(10,2) NULL,                -- snapshot when closing
  counted_amount  DECIMAL(10,2) NULL,
  difference      DECIMAL(10,2) NULL,                -- counted - expected (negative = missing)
  notes           VARCHAR(255) NULL,
  closed_by       INT UNSIGNED NULL,
  closed_at       DATETIME NULL,
  CONSTRAINT uq_cash_sessions_date UNIQUE (business_date),
  CONSTRAINT fk_cash_opened_by FOREIGN KEY (opened_by) REFERENCES users (id),
  CONSTRAINT fk_cash_closed_by FOREIGN KEY (closed_by) REFERENCES users (id),
  CONSTRAINT chk_cash_opening CHECK (opening_amount >= 0),
  CONSTRAINT chk_cash_counted CHECK (counted_amount IS NULL OR counted_amount >= 0),
  CONSTRAINT chk_cash_closed  CHECK (
    (closed_at IS NULL AND counted_amount IS NULL) OR
    (closed_at IS NOT NULL AND counted_amount IS NOT NULL AND expected_amount IS NOT NULL)
  )
) ENGINE = InnoDB;
