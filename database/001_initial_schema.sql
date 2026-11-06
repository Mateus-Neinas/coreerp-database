-- CoreERP — schema inicial (PostgreSQL)
-- Execute em um banco vazio. Cada migração registra sua versão em schema_migrations.
BEGIN;

CREATE TABLE IF NOT EXISTS schema_migrations (
  version text PRIMARY KEY,
  description text NOT NULL,
  applied_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS organizations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL CHECK (length(trim(name)) > 0),
  slug text NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9][a-z0-9-]{1,62}$'),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL UNIQUE CHECK (position('@' in email) > 1),
  full_name text NOT NULL CHECK (length(trim(full_name)) > 0),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS organization_members (
  organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('owner', 'admin', 'operator', 'finance', 'viewer')),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (organization_id, user_id)
);

CREATE TABLE IF NOT EXISTS customers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name text NOT NULL CHECK (length(trim(name)) > 0),
  email text,
  phone text,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, id)
);
CREATE INDEX IF NOT EXISTS customers_org_name_idx ON customers (organization_id, name);

CREATE TABLE IF NOT EXISTS suppliers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name text NOT NULL CHECK (length(trim(name)) > 0),
  email text,
  phone text,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, id)
);
CREATE INDEX IF NOT EXISTS suppliers_org_name_idx ON suppliers (organization_id, name);

CREATE TABLE IF NOT EXISTS products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  sku text NOT NULL CHECK (length(trim(sku)) > 0),
  name text NOT NULL CHECK (length(trim(name)) > 0),
  unit text NOT NULL DEFAULT 'un',
  sale_price_cents bigint NOT NULL DEFAULT 0 CHECK (sale_price_cents >= 0),
  cost_price_cents bigint NOT NULL DEFAULT 0 CHECK (cost_price_cents >= 0),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, sku)
);
CREATE INDEX IF NOT EXISTS products_org_name_idx ON products (organization_id, name);

CREATE TABLE IF NOT EXISTS warehouses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  code text NOT NULL CHECK (length(trim(code)) > 0),
  name text NOT NULL CHECK (length(trim(name)) > 0),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, code)
);

CREATE TABLE IF NOT EXISTS inventory_balances (
  organization_id uuid NOT NULL,
  warehouse_id uuid NOT NULL,
  product_id uuid NOT NULL,
  quantity numeric(14,3) NOT NULL DEFAULT 0 CHECK (quantity >= 0),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (organization_id, warehouse_id, product_id),
  FOREIGN KEY (organization_id, warehouse_id)
    REFERENCES warehouses (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, product_id)
    REFERENCES products (organization_id, id) ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS stock_movements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  warehouse_id uuid NOT NULL,
  product_id uuid NOT NULL,
  movement_type text NOT NULL CHECK (movement_type IN ('receipt', 'issue', 'adjustment')),
  quantity_delta numeric(14,3) NOT NULL CHECK (quantity_delta <> 0),
  reference_type text,
  reference_id uuid,
  note text,
  created_by_user_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, id),
  CHECK (
    (movement_type = 'receipt' AND quantity_delta > 0)
    OR (movement_type = 'issue' AND quantity_delta < 0)
    OR movement_type = 'adjustment'
  ),
  FOREIGN KEY (organization_id, warehouse_id)
    REFERENCES warehouses (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, product_id)
    REFERENCES products (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, created_by_user_id)
    REFERENCES organization_members (organization_id, user_id) ON DELETE RESTRICT
);
CREATE INDEX IF NOT EXISTS stock_movements_org_product_date_idx
  ON stock_movements (organization_id, product_id, created_at DESC);

CREATE TABLE IF NOT EXISTS sales_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  customer_id uuid NOT NULL,
  order_number text NOT NULL,
  status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'confirmed', 'fulfilled', 'cancelled')),
  total_cents bigint NOT NULL DEFAULT 0 CHECK (total_cents >= 0),
  created_by_user_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, order_number),
  FOREIGN KEY (organization_id, customer_id)
    REFERENCES customers (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, created_by_user_id)
    REFERENCES organization_members (organization_id, user_id) ON DELETE RESTRICT
);
CREATE INDEX IF NOT EXISTS sales_orders_org_status_date_idx
  ON sales_orders (organization_id, status, created_at DESC);

CREATE TABLE IF NOT EXISTS sales_order_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  sales_order_id uuid NOT NULL,
  product_id uuid NOT NULL,
  quantity numeric(14,3) NOT NULL CHECK (quantity > 0),
  unit_price_cents bigint NOT NULL CHECK (unit_price_cents >= 0),
  line_total_cents bigint NOT NULL CHECK (line_total_cents >= 0),
  UNIQUE (organization_id, id),
  FOREIGN KEY (organization_id, sales_order_id)
    REFERENCES sales_orders (organization_id, id) ON DELETE CASCADE,
  FOREIGN KEY (organization_id, product_id)
    REFERENCES products (organization_id, id) ON DELETE RESTRICT,
  CHECK (line_total_cents = round(quantity * unit_price_cents)::bigint)
);

CREATE TABLE IF NOT EXISTS purchase_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  supplier_id uuid NOT NULL,
  purchase_number text NOT NULL,
  status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'submitted', 'partially_received', 'received', 'cancelled')),
  total_cents bigint NOT NULL DEFAULT 0 CHECK (total_cents >= 0),
  created_by_user_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, purchase_number),
  FOREIGN KEY (organization_id, supplier_id)
    REFERENCES suppliers (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, created_by_user_id)
    REFERENCES organization_members (organization_id, user_id) ON DELETE RESTRICT
);
CREATE INDEX IF NOT EXISTS purchase_orders_org_status_date_idx
  ON purchase_orders (organization_id, status, created_at DESC);

CREATE TABLE IF NOT EXISTS purchase_order_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  purchase_order_id uuid NOT NULL,
  product_id uuid NOT NULL,
  quantity numeric(14,3) NOT NULL CHECK (quantity > 0),
  unit_cost_cents bigint NOT NULL CHECK (unit_cost_cents >= 0),
  line_total_cents bigint NOT NULL CHECK (line_total_cents >= 0),
  UNIQUE (organization_id, id),
  FOREIGN KEY (organization_id, purchase_order_id)
    REFERENCES purchase_orders (organization_id, id) ON DELETE CASCADE,
  FOREIGN KEY (organization_id, product_id)
    REFERENCES products (organization_id, id) ON DELETE RESTRICT,
  CHECK (line_total_cents = round(quantity * unit_cost_cents)::bigint)
);

CREATE TABLE IF NOT EXISTS financial_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  entry_type text NOT NULL CHECK (entry_type IN ('receivable', 'payable')),
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'partial', 'paid', 'void')),
  customer_id uuid,
  supplier_id uuid,
  sales_order_id uuid,
  purchase_order_id uuid,
  description text NOT NULL CHECK (length(trim(description)) > 0),
  amount_cents bigint NOT NULL CHECK (amount_cents > 0),
  due_on date NOT NULL,
  paid_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, id),
  CHECK (
    (entry_type = 'receivable' AND customer_id IS NOT NULL AND supplier_id IS NULL)
    OR (entry_type = 'payable' AND supplier_id IS NOT NULL AND customer_id IS NULL)
  ),
  CHECK (
    (entry_type = 'receivable' AND purchase_order_id IS NULL)
    OR (entry_type = 'payable' AND sales_order_id IS NULL)
  ),
  FOREIGN KEY (organization_id, customer_id)
    REFERENCES customers (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, supplier_id)
    REFERENCES suppliers (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, sales_order_id)
    REFERENCES sales_orders (organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, purchase_order_id)
    REFERENCES purchase_orders (organization_id, id) ON DELETE RESTRICT
);
CREATE INDEX IF NOT EXISTS financial_entries_org_type_status_due_idx
  ON financial_entries (organization_id, entry_type, status, due_on);

INSERT INTO schema_migrations (version, description)
VALUES ('001', 'initial multi-tenant ERP schema')
ON CONFLICT (version) DO NOTHING;

COMMIT;
