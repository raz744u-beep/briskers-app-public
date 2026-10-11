-- Dev review migration: deduplicated offline received-payment replay.
-- A single database transaction atomically records the idempotency key and
-- creates the same pending payment used by normal online entry.
CREATE TABLE IF NOT EXISTS briskers.invoice_payment_operation_keys (
  business_id uuid NOT NULL,
  operation_id uuid NOT NULL,
  invoice_id uuid NOT NULL,
  method_id uuid NOT NULL,
  amount numeric(14,2) NOT NULL,
  pending_payment_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (business_id, operation_id)
);
ALTER TABLE briskers.invoice_payment_operation_keys ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON briskers.invoice_payment_operation_keys FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.briskers_add_pending_invoice_payment_once(
  p_business_id uuid,
  p_invoice_id uuid,
  p_amount numeric,
  p_method_id uuid,
  p_operation_id uuid
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE
  v_key briskers.invoice_payment_operation_keys%ROWTYPE;
  v_payment_id uuid;
BEGIN
  PERFORM briskers.require_permission(p_business_id, 'payments.create');
  IF p_operation_id IS NULL OR p_invoice_id IS NULL OR p_method_id IS NULL
     OR p_amount IS NULL OR p_amount <= 0
     OR p_amount <> round(p_amount,2) THEN
    RAISE EXCEPTION 'Invalid offline payment request' USING ERRCODE='22023';
  END IF;

  INSERT INTO briskers.invoice_payment_operation_keys (
    business_id, operation_id, invoice_id, method_id, amount
  ) VALUES (
    p_business_id, p_operation_id, p_invoice_id, p_method_id, p_amount
  ) ON CONFLICT (business_id, operation_id) DO NOTHING;

  SELECT * INTO STRICT v_key
  FROM briskers.invoice_payment_operation_keys
  WHERE business_id = p_business_id AND operation_id = p_operation_id
  FOR UPDATE;

  IF v_key.invoice_id IS DISTINCT FROM p_invoice_id
     OR v_key.method_id IS DISTINCT FROM p_method_id
     OR v_key.amount IS DISTINCT FROM p_amount THEN
    RAISE EXCEPTION 'Payment operation key reused with different details'
      USING ERRCODE='23505';
  END IF;

  IF v_key.pending_payment_id IS NOT NULL THEN
    RETURN v_key.pending_payment_id;
  END IF;

  -- Underlying RPC performs permission, invoice balance, and active method
  -- checks. This call + key update are in the same database transaction.
  v_payment_id := public.briskers_add_pending_invoice_payment(
    p_business_id, p_invoice_id, p_amount, p_method_id
  );

  UPDATE briskers.invoice_payment_operation_keys
  SET pending_payment_id = v_payment_id
  WHERE business_id = p_business_id AND operation_id = p_operation_id;
  RETURN v_payment_id;
END;
$function$;
REVOKE ALL ON FUNCTION public.briskers_add_pending_invoice_payment_once(uuid,uuid,numeric,uuid,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.briskers_add_pending_invoice_payment_once(uuid,uuid,numeric,uuid,uuid) TO authenticated;
