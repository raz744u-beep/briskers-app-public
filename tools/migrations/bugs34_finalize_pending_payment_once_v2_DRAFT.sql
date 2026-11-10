-- Bugs 34 DRAFT ONLY. DO NOT DEPLOY without synthetic SQL and Owner approval.
-- This is a separate opt-in RPC, not a replacement for the legacy finalizer.
-- It never accepts amounts or new receipt IDs from the caller.
CREATE OR REPLACE FUNCTION public.briskers_finalize_pending_invoice_payment_once_v2(
  p_business_id uuid, p_invoice_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  d briskers.sales_documents%ROWTYPE;
  p briskers.invoice_pending_payments%ROWTYPE;
  k briskers.invoice_payment_operation_keys%ROWTYPE;
  v_tx uuid;
  v_mapping jsonb := '[]'::jsonb;
  v_count integer := 0;
  v_expected_count integer := 0;
  v_expected_total numeric := 0;
  v_posted_total numeric := 0;
BEGIN
  PERFORM briskers.require_permission(p_business_id,'payments.create');
  SELECT * INTO d FROM briskers.sales_documents
   WHERE business_id=p_business_id AND id=p_invoice_id FOR UPDATE;
  IF NOT FOUND OR d.kind <> 'invoice' OR d.status NOT IN ('issued','accepted') THEN
    RAISE EXCEPTION 'Issued invoice required' USING ERRCODE='23514';
  END IF;
  SELECT count(*),coalesce(sum(amount),0)
    INTO v_expected_count,v_expected_total
    FROM briskers.invoice_payment_operation_keys
   WHERE business_id=p_business_id AND invoice_id=p_invoice_id;
  IF v_expected_count=0 OR v_expected_total IS DISTINCT FROM d.total_amount THEN
    RAISE EXCEPTION 'Original receipt coverage does not match invoice total'
      USING ERRCODE='23514';
  END IF;
  -- Reject mixed legacy posted and pending payments before any write.
  IF EXISTS (SELECT 1 FROM briskers.payment_allocations a
      WHERE a.business_id=p_business_id AND a.document_id=p_invoice_id)
     AND EXISTS (SELECT 1 FROM briskers.invoice_pending_payments x
      WHERE x.business_id=p_business_id AND x.invoice_id=p_invoice_id) THEN
    RAISE EXCEPTION 'Mixed posted and pending payments require reconciliation'
      USING ERRCODE='23514';
  END IF;
  -- No partial finalization: every pending row must have exactly one original
  -- operation mapping and its immutable financial attributes must agree.
  FOR p IN SELECT * FROM briskers.invoice_pending_payments
      WHERE business_id=p_business_id AND invoice_id=p_invoice_id
      ORDER BY entered_at,id FOR UPDATE
  LOOP
    SELECT * INTO k FROM briskers.invoice_payment_operation_keys
      WHERE business_id=p_business_id AND invoice_id=p_invoice_id
        AND pending_payment_id=p.id FOR UPDATE;
    IF NOT FOUND OR k.operation_id IS NULL OR k.amount IS DISTINCT FROM p.amount
       OR k.method_id IS DISTINCT FROM p.payment_method_id
       OR (k.payment_date IS NOT NULL AND k.payment_date IS DISTINCT FROM
           COALESCE(p.payment_date,p.entered_at::date)) THEN
      RAISE EXCEPTION 'Pending payment identity needs reconciliation'
        USING ERRCODE='23514';
    END IF;
    -- Reuses existing posted transaction on exact replay, not a random UUID.
    v_tx := public.briskers_record_payment(
      p_business_id,p_invoice_id,p.account_id,p.amount,
      k.operation_id,COALESCE(p.payment_date,p.entered_at::date),
      p.payment_method_id
    );
    v_mapping := v_mapping || jsonb_build_array(jsonb_build_object(
      'operation_id',k.operation_id,'pending_payment_id',p.id,
      'transaction_id',v_tx,'amount',p.amount
    ));
    DELETE FROM briskers.invoice_pending_payments
      WHERE business_id=p_business_id AND id=p.id;
    v_count := v_count + 1;
  END LOOP;
  IF v_count = 0 THEN
    -- On lost response, verify original identities and posted allocations.
    FOR k IN SELECT * FROM briskers.invoice_payment_operation_keys
      WHERE business_id=p_business_id AND invoice_id=p_invoice_id
      ORDER BY created_at,operation_id
    LOOP
      SELECT t.id INTO v_tx
      FROM briskers.financial_transactions t
      JOIN briskers.payment_allocations a
        ON a.business_id=t.business_id AND a.transaction_id=t.id
      WHERE t.business_id=p_business_id
        AND t.idempotency_key=k.operation_id
        AND t.kind='customer_payment' AND t.status='posted'
        AND t.amount=k.amount
        AND t.payment_method_id IS NOT DISTINCT FROM k.method_id
        AND a.document_id=p_invoice_id AND a.gross_amount=k.amount;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Previously received payment not fully reconciled'
          USING ERRCODE='23514';
      END IF;
      v_mapping := v_mapping || jsonb_build_array(jsonb_build_object(
        'operation_id',k.operation_id,'pending_payment_id',k.pending_payment_id,
        'transaction_id',v_tx,'amount',k.amount
      ));
      v_count := v_count + 1;
    END LOOP;
    IF v_count = 0 THEN
      RAISE EXCEPTION 'No original payment identities found'
        USING ERRCODE='23514';
    END IF;
  END IF;
  SELECT coalesce(sum(a.gross_amount),0) INTO v_posted_total
    FROM briskers.payment_allocations a
    JOIN briskers.financial_transactions t
      ON t.business_id=a.business_id AND t.id=a.transaction_id
   WHERE a.business_id=p_business_id AND a.document_id=p_invoice_id
     AND t.status='posted';
  IF v_posted_total IS DISTINCT FROM d.total_amount
     OR jsonb_array_length(v_mapping) <> v_expected_count THEN
    RAISE EXCEPTION 'Posted payment coverage incomplete'
      USING ERRCODE='23514';
  END IF;
  RETURN v_mapping;
END
$function$;
