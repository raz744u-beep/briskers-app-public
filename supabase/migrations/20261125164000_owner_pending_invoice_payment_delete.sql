CREATE TABLE IF NOT EXISTS briskers.owner_pending_invoice_payment_deletions_v1 (
  business_id uuid NOT NULL,
  invoice_id uuid NOT NULL,
  operation_id uuid,
  payment_id uuid,
  CHECK (operation_id IS NOT NULL OR payment_id IS NOT NULL),
  UNIQUE (business_id,operation_id),
  UNIQUE (business_id,payment_id)
);
ALTER TABLE briskers.owner_pending_invoice_payment_deletions_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON briskers.owner_pending_invoice_payment_deletions_v1 FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION briskers.reject_canceled_invoice_payment_create_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $body$
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'briskers:invoice-payment-create:'||NEW.business_id::text||':'||NEW.operation_id::text,0));
  IF EXISTS (
    SELECT 1 FROM briskers.owner_pending_invoice_payment_deletions_v1 d
    WHERE d.business_id=NEW.business_id AND d.operation_id=NEW.operation_id
  ) THEN
    RAISE EXCEPTION 'This pending receipt was removed by the Owner' USING ERRCODE='PT409';
  END IF;
  RETURN NEW;
END
$body$;
REVOKE ALL ON FUNCTION briskers.reject_canceled_invoice_payment_create_v1() FROM PUBLIC;
DROP TRIGGER IF EXISTS briskers_reject_canceled_invoice_payment_create_v1
  ON briskers.invoice_payment_operation_keys;
CREATE TRIGGER briskers_reject_canceled_invoice_payment_create_v1
  BEFORE INSERT ON briskers.invoice_payment_operation_keys
  FOR EACH ROW EXECUTE FUNCTION briskers.reject_canceled_invoice_payment_create_v1();

CREATE OR REPLACE FUNCTION public.briskers_owner_delete_pending_invoice_payment_v1(
  p_business_id uuid, p_invoice_id uuid, p_payment_id uuid, p_create_operation uuid
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $body$
DECLARE
  payment uuid := p_payment_id;
  prior briskers.owner_pending_invoice_payment_deletions_v1%ROWTYPE;
  receipt_key briskers.invoice_payment_operation_keys%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR briskers.is_owner(p_business_id) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Owner access required' USING ERRCODE='42501';
  END IF;
  IF p_invoice_id IS NULL OR (p_payment_id IS NULL) = (p_create_operation IS NULL) THEN
    RAISE EXCEPTION 'An invoice and exactly one receipt identity are required' USING ERRCODE='22023';
  END IF;
  IF p_create_operation IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtextextended(
      'briskers:invoice-payment-create:'||p_business_id::text||':'||p_create_operation::text,0));
    SELECT k.* INTO receipt_key FROM briskers.invoice_payment_operation_keys k
    WHERE k.business_id=p_business_id AND k.operation_id=p_create_operation;
    IF FOUND THEN
      IF receipt_key.invoice_id IS DISTINCT FROM p_invoice_id THEN
        RAISE EXCEPTION 'Receipt belongs to a different invoice' USING ERRCODE='PT409';
      END IF;
      payment := receipt_key.pending_payment_id;
      IF payment IS NULL THEN
        RAISE EXCEPTION 'Receipt identity cannot be verified' USING ERRCODE='PT409';
      END IF;
    END IF;
  END IF;

  -- Finalization takes this same invoice lock before posting a receipt.
  PERFORM 1 FROM briskers.sales_documents d
  WHERE d.business_id=p_business_id AND d.id=p_invoice_id AND d.kind='invoice'
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invoice identity cannot be verified' USING ERRCODE='PT409';
  END IF;
  SELECT d.* INTO prior FROM briskers.owner_pending_invoice_payment_deletions_v1 d
  WHERE d.business_id=p_business_id AND d.invoice_id=p_invoice_id AND
    (d.operation_id=p_create_operation OR d.payment_id=payment)
  LIMIT 1;
  IF FOUND THEN RETURN prior.payment_id; END IF;

  IF payment IS NOT NULL THEN
    DELETE FROM briskers.invoice_pending_payments p
    WHERE p.business_id=p_business_id AND p.invoice_id=p_invoice_id AND p.id=payment;
    IF NOT FOUND THEN
      -- The old endpoint or another device may already have finalized it.
      -- Absence alone is not proof that this deletion succeeded.
      RAISE EXCEPTION 'Pending receipt is no longer available. Review invoice payments.'
        USING ERRCODE='PT409';
    END IF;
  END IF;
  INSERT INTO briskers.owner_pending_invoice_payment_deletions_v1
    (business_id,invoice_id,operation_id,payment_id)
  VALUES (p_business_id,p_invoice_id,p_create_operation,payment);
  RETURN payment;
END
$body$;
REVOKE ALL ON FUNCTION public.briskers_owner_delete_pending_invoice_payment_v1(uuid,uuid,uuid,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.briskers_owner_delete_pending_invoice_payment_v1(uuid,uuid,uuid,uuid)
  TO authenticated;
