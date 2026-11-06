-- CoreERP — saldo de estoque derivado do livro imutável de movimentos.
BEGIN;

CREATE OR REPLACE FUNCTION coreerp_apply_stock_movement()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO inventory_balances (
    organization_id, warehouse_id, product_id, quantity, updated_at
  )
  VALUES (
    NEW.organization_id, NEW.warehouse_id, NEW.product_id,
    NEW.quantity_delta, now()
  )
  ON CONFLICT (organization_id, warehouse_id, product_id)
  DO UPDATE SET
    quantity = inventory_balances.quantity + EXCLUDED.quantity,
    updated_at = now()
  WHERE inventory_balances.quantity + EXCLUDED.quantity >= 0;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'insufficient_stock'
      USING ERRCODE = '23514',
            HINT = 'A movimentação deixaria o saldo do depósito negativo.';
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION coreerp_reject_stock_movement_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'stock_movements_are_append_only'
    USING ERRCODE = '55000',
          HINT = 'Registre uma movimentação inversa para corrigir o saldo.';
END;
$$;

DROP TRIGGER IF EXISTS stock_movement_apply_balance ON stock_movements;
CREATE TRIGGER stock_movement_apply_balance
AFTER INSERT ON stock_movements
FOR EACH ROW EXECUTE FUNCTION coreerp_apply_stock_movement();

DROP TRIGGER IF EXISTS stock_movement_append_only ON stock_movements;
CREATE TRIGGER stock_movement_append_only
BEFORE UPDATE OR DELETE ON stock_movements
FOR EACH ROW EXECUTE FUNCTION coreerp_reject_stock_movement_mutation();

INSERT INTO schema_migrations (version, description)
VALUES ('002', 'transactional stock ledger and balance projection')
ON CONFLICT (version) DO NOTHING;

COMMIT;
