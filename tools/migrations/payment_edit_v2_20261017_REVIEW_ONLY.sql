-- Briskers payment date v2 — CODE REVIEW ONLY.
-- Do not apply to the active Briskers shop project without separate approval.
-- Tested only with synthetic records on an isolated environment.
BEGIN;
ALTER TABLE briskers.invoice_pending_payments
  ADD COLUMN IF NOT EXISTS payment_date date;
ALTER TABLE briskers.invoice_payment_operation_keys
  ADD COLUMN IF NOT EXISTS payment_date date;
-- Client-reported edits made before the first server receipt. This is an
-- audit trail, not server-verified financial history.
ALTER TABLE briskers.invoice_payment_operation_keys
  ADD COLUMN IF NOT EXISTS local_edit_history jsonb
  NOT NULL DEFAULT '[]'::jsonb;

CREATE TABLE IF NOT EXISTS briskers.invoice_pending_payment_edit_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id uuid NOT NULL,
  invoice_id uuid NOT NULL,
  payment_id uuid NOT NULL,
  changed_by uuid,
  old_amount numeric NOT NULL,
  new_amount numeric NOT NULL,
  old_payment_method_id uuid,
  new_payment_method_id uuid,
  old_payment_date date,
  new_payment_date date,
  prior_row_version bigint NOT NULL,
  source text NOT NULL DEFAULT 'owner_edit',
  changed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX IF NOT EXISTS idx_pending_payment_edit_audit_payment
  ON briskers.invoice_pending_payment_edit_audit
  (business_id, payment_id, changed_at DESC);
ALTER TABLE briskers.invoice_pending_payment_edit_audit ENABLE ROW LEVEL SECURITY;
-- Audit rows are written only from permission-checked SECURITY DEFINER RPCs.
REVOKE ALL ON TABLE briskers.invoice_pending_payment_edit_audit FROM PUBLIC;

-- A new separate function protects old idempotency clients. No automatic
-- update of already accepted legacy operations with a different date.
CREATE OR REPLACE FUNCTION public.briskers_add_pending_invoice_payment_once_v2(
  p_business_id uuid, p_invoice_id uuid, p_amount numeric,
  p_method_id uuid, p_operation_id uuid, p_payment_date date,
  p_local_edit_history jsonb DEFAULT '[]'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE
  v_existing briskers.invoice_payment_operation_keys%ROWTYPE;
  v_id uuid;
  v_date date;
BEGIN
  PERFORM briskers.require_permission(p_business_id, 'payments.create');
  IF p_payment_date IS NULL OR p_payment_date < DATE '1990-01-01'
     OR p_payment_date > current_date + 1
     OR p_local_edit_history IS NULL
     OR jsonb_typeof(p_local_edit_history) IS DISTINCT FROM 'array'
     OR jsonb_array_length(p_local_edit_history) > 100 THEN
    RAISE EXCEPTION 'Invalid payment date' USING ERRCODE='22023';
  END IF;
  -- Two concurrent uses of this UUID serialize in the v1 function, which
  -- inserts and locks the operation key before creating a payment.
  SELECT * INTO v_existing FROM briskers.invoice_payment_operation_keys
   WHERE business_id=p_business_id AND operation_id=p_operation_id
   FOR UPDATE;
  IF FOUND AND (v_existing.payment_date IS DISTINCT FROM p_payment_date
      OR v_existing.invoice_id IS DISTINCT FROM p_invoice_id
      OR v_existing.method_id IS DISTINCT FROM p_method_id
      OR v_existing.amount IS DISTINCT FROM p_amount
      OR v_existing.local_edit_history IS DISTINCT FROM p_local_edit_history) THEN
    RAISE EXCEPTION 'Payment operation key reused with different details'
      USING ERRCODE='23505';
  END IF;
  v_id := public.briskers_add_pending_invoice_payment_once(
    p_business_id, p_invoice_id, p_amount, p_method_id, p_operation_id);
  UPDATE briskers.invoice_payment_operation_keys
     SET payment_date=p_payment_date,
         local_edit_history=p_local_edit_history
   WHERE business_id=p_business_id AND operation_id=p_operation_id
     AND payment_date IS NULL;
  SELECT payment_date INTO v_date
    FROM briskers.invoice_pending_payments
    WHERE business_id=p_business_id AND id=v_id FOR UPDATE;
  IF NOT FOUND THEN
    -- A previously finalized receipt can no longer be modified in place.
    RAISE EXCEPTION 'Payment already finalized; no new charge created'
      USING ERRCODE='23514';
  END IF;
  IF v_date IS NOT NULL AND v_date IS DISTINCT FROM p_payment_date THEN
    RAISE EXCEPTION 'Payment date mismatch on already received operation'
      USING ERRCODE='23505';
  END IF;
  UPDATE briskers.invoice_pending_payments
     SET payment_date=p_payment_date
   WHERE business_id=p_business_id AND id=v_id
     AND payment_date IS NULL;
  RETURN v_id;
END;
$fn$;
REVOKE ALL ON FUNCTION public.briskers_add_pending_invoice_payment_once_v2(
  uuid,uuid,numeric,uuid,uuid,date,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.briskers_add_pending_invoice_payment_once_v2(
  uuid,uuid,numeric,uuid,uuid,date,jsonb) TO authenticated;

-- Server-pending edits use the payment row version and a stable payment ID.
-- Lock order: invoice, then pending payment (same as finalization).
-- The original entered_by and entered_at are immutable receipt provenance:
-- edits record auth.uid() in the separate audit table only.
CREATE OR REPLACE FUNCTION public.briskers_update_pending_invoice_payment_v2(
  p_business_id uuid, p_payment_id uuid, p_amount numeric,
  p_method_id uuid, p_payment_date date, p_expected_row_version bigint
)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE
  v_invoice_id uuid;
  d briskers.sales_documents%ROWTYPE;
  p briskers.invoice_pending_payments%ROWTYPE;
  v_account uuid;
  v_paid numeric;
  v_others numeric;
BEGIN
  PERFORM briskers.require_permission(p_business_id, 'payments.create');
  IF p_amount IS NULL OR p_amount<=0 OR p_amount>999999999999.99
     OR p_amount<>round(p_amount,2) OR p_method_id IS NULL
     OR p_expected_row_version IS NULL OR p_payment_date IS NULL
     OR p_payment_date < DATE '1990-01-01'
     OR p_payment_date > current_date + 1 THEN
    RAISE EXCEPTION 'Invalid payment edit' USING ERRCODE='22023';
  END IF;
  SELECT invoice_id INTO v_invoice_id
    FROM briskers.invoice_pending_payments
   WHERE business_id=p_business_id AND id=p_payment_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payment is no longer pending' USING ERRCODE='P0002';
  END IF;
  SELECT * INTO d FROM briskers.sales_documents
    WHERE business_id=p_business_id AND id=v_invoice_id FOR UPDATE;
  IF NOT FOUND OR d.kind<>'invoice' OR d.status='void' THEN
    RAISE EXCEPTION 'Invoice unavailable for payment correction' USING ERRCODE='23514';
  END IF;
  SELECT * INTO p FROM briskers.invoice_pending_payments
    WHERE business_id=p_business_id AND id=p_payment_id FOR UPDATE;
  IF NOT FOUND OR p.invoice_id IS DISTINCT FROM v_invoice_id THEN
    RAISE EXCEPTION 'Pending payment changed; reload before editing'
      USING ERRCODE='40001';
  END IF;
  IF p.row_version<>p_expected_row_version THEN
    RAISE EXCEPTION 'Payment changed on another device; reload and review'
      USING ERRCODE='40001';
  END IF;
  SELECT default_account_id INTO v_account FROM briskers.payment_methods
    WHERE business_id=p_business_id AND id=p_method_id AND active;
  IF v_account IS NULL THEN
    RAISE EXCEPTION 'Payment method unavailable' USING ERRCODE='23514';
  END IF;
  SELECT COALESCE(SUM(a.gross_amount),0) INTO v_paid
    FROM briskers.payment_allocations a
    JOIN briskers.financial_transactions t
      ON t.business_id=a.business_id AND t.id=a.transaction_id
   WHERE a.business_id=p_business_id AND a.document_id=v_invoice_id
     AND t.status='posted';
  SELECT COALESCE(SUM(x.amount),0) INTO v_others
    FROM briskers.invoice_pending_payments x
   WHERE x.business_id=p_business_id AND x.invoice_id=v_invoice_id
     AND x.id<>p_payment_id;
  IF p_amount > greatest(d.total_amount-v_paid-v_others,0)+0.005 THEN
    RAISE EXCEPTION 'Payment exceeds remaining invoice balance'
      USING ERRCODE='23514';
  END IF;
  INSERT INTO briskers.invoice_pending_payment_edit_audit (
    business_id,invoice_id,payment_id,changed_by,
    old_amount,new_amount,old_payment_method_id,new_payment_method_id,
    old_payment_date,new_payment_date,prior_row_version
  ) VALUES (
    p_business_id,v_invoice_id,p_payment_id,auth.uid(),
    p.amount,round(p_amount,2),p.payment_method_id,p_method_id,
    p.payment_date,p_payment_date,p.row_version
  );
  UPDATE briskers.invoice_pending_payments
     SET amount=round(p_amount,2), payment_method_id=p_method_id,
         account_id=v_account, payment_date=p_payment_date,
         updated_at=clock_timestamp(),
         row_version=row_version+1
   WHERE business_id=p_business_id AND id=p_payment_id;
  -- An old, identical replay cannot create a second receipt. Any stale
  -- retry with original amount/method now conflicts with operation-key data.
  UPDATE briskers.invoice_payment_operation_keys
     SET amount=round(p_amount,2), method_id=p_method_id,
         payment_date=p_payment_date
   WHERE business_id=p_business_id AND pending_payment_id=p_payment_id;
  RETURN true;
END;
$fn$;
REVOKE ALL ON FUNCTION public.briskers_update_pending_invoice_payment_v2(
  uuid,uuid,numeric,uuid,date,bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.briskers_update_pending_invoice_payment_v2(
  uuid,uuid,numeric,uuid,date,bigint) TO authenticated;

-- Preserve historical receipt_date in posted accounting: previous code passed
-- current_date, which is incorrect for payments received yesterday/offline.
CREATE OR REPLACE FUNCTION public.briskers_finalize_pending_invoice_payment(
  p_business_id uuid, p_invoice_id uuid
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE
  d briskers.sales_documents%ROWTYPE;
  p record;
  v_tx uuid;
  v_last_tx uuid;
BEGIN
  PERFORM briskers.require_permission(p_business_id,'payments.create');
  SELECT * INTO d
  FROM briskers.sales_documents
  WHERE business_id=p_business_id AND id=p_invoice_id FOR UPDATE;
  IF NOT FOUND OR d.kind<>'invoice' THEN
    RAISE EXCEPTION 'Invoice not found' USING ERRCODE='P0002';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM briskers.invoice_pending_payments x
    WHERE x.business_id=p_business_id AND x.invoice_id=p_invoice_id
  ) THEN
    RAISE EXCEPTION 'No pending payment was entered for this invoice'
      USING ERRCODE='P0002';
  END IF;
  IF d.document_number IS NULL OR d.status='draft' THEN
    PERFORM public.briskers_issue_document(
      p_business_id,p_invoice_id,d.row_version,current_date
    );
  END IF;
  FOR p IN
    SELECT * FROM briskers.invoice_pending_payments
    WHERE business_id=p_business_id AND invoice_id=p_invoice_id
    ORDER BY entered_at,id FOR UPDATE
  LOOP
    v_tx := public.briskers_record_payment(
      p_business_id,p_invoice_id,p.account_id,p.amount,
      gen_random_uuid(),COALESCE(p.payment_date,current_date),
      p.payment_method_id
    );
    v_last_tx := v_tx;
    DELETE FROM briskers.invoice_pending_payments
      WHERE business_id=p_business_id AND id=p.id;
  END LOOP;
  RETURN v_last_tx;
END;
$fn$;

-- v3 stays available to existing clients; new clients opt into v4 to read
-- row_version and separate payment_date without rewriting entered_at.
CREATE OR REPLACE FUNCTION public.briskers_document_detail_v4(
  p_business_id uuid, p_document_id uuid
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE
  v jsonb;
  v_payments jsonb;
BEGIN
  v := public.briskers_document_detail_v3(p_business_id,p_document_id);
  SELECT COALESCE(jsonb_agg(
    CASE WHEN p.id IS NOT NULL THEN
      x.entry || jsonb_build_object(
        'payment_date',p.payment_date, 'row_version',p.row_version)
    WHEN t.id IS NOT NULL THEN
      x.entry || jsonb_build_object('payment_date',t.transaction_date)
    ELSE x.entry END
    ORDER BY x.position
  ),'[]'::jsonb) INTO v_payments
  FROM jsonb_array_elements(COALESCE(v->'payments','[]'::jsonb))
      WITH ORDINALITY AS x(entry,position)
  LEFT JOIN briskers.invoice_pending_payments p
    ON p.business_id=p_business_id AND p.id::text=x.entry->>'id'
  LEFT JOIN briskers.financial_transactions t
    ON t.business_id=p_business_id AND t.id::text=x.entry->>'id'
       AND t.status='posted';
  RETURN jsonb_set(v,'{payments}',v_payments,true);
END;
$fn$;
REVOKE ALL ON FUNCTION public.briskers_document_detail_v4(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.briskers_document_detail_v4(uuid,uuid)
  TO authenticated;
-- Existing pending-receipt inventory must show corrected business dates.
-- Preserve its RPC name, authentication, permission checks and response shape.
-- Only the pending receipt date expression changes; posted transactions
-- already use t.transaction_date. No existing payment records are rewritten.
CREATE OR REPLACE FUNCTION public.briskers_invoice_receipts_v1(p_business_id uuid, p_limit integer DEFAULT 250, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_result jsonb;
BEGIN
  PERFORM briskers.require_permission(p_business_id, 'expenses.read');
  PERFORM briskers.require_permission(p_business_id, 'invoices.read');

  WITH receipts AS (
    SELECT
      'pending'::text AS receipt_state,
      p.id AS receipt_id,
      NULL::uuid AS transaction_id,
      k.operation_id AS operation_id,
      p.invoice_id,
      p.amount AS receipt_amount,
      p.entered_at AS receipt_time,
      COALESCE(p.payment_date, p.entered_at::date) AS receipt_date,
      p.payment_method_id
    FROM briskers.invoice_pending_payments p
    LEFT JOIN LATERAL (
      SELECT k.operation_id
      FROM briskers.invoice_payment_operation_keys k
      WHERE k.business_id=p.business_id
        AND k.pending_payment_id=p.id
      ORDER BY k.created_at DESC
      LIMIT 1
    ) k ON true
    WHERE p.business_id=p_business_id
    UNION ALL
    SELECT
      'posted'::text, a.id, t.id, t.idempotency_key, a.document_id,
      a.gross_amount, t.created_at, t.transaction_date, t.payment_method_id
    FROM briskers.payment_allocations a
    JOIN briskers.financial_transactions t
      ON t.business_id=a.business_id AND t.id=a.transaction_id
     AND t.status='posted' AND t.kind='customer_payment'
    WHERE a.business_id=p_business_id
  ), enriched AS (
    SELECT
      r.*, d.total_amount AS invoice_total, d.document_number,
      c.display_name AS customer_name, j.job_number,
      COALESCE(pm.name, 'Payment') AS payment_method,
      SUM(r.receipt_amount) OVER (
        PARTITION BY r.invoice_id
        ORDER BY r.receipt_time, r.receipt_id
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      ) AS covered_amount
    FROM receipts r
    JOIN briskers.sales_documents d
      ON d.business_id=p_business_id AND d.id=r.invoice_id
      AND d.kind='invoice' AND d.status<>'void'
    JOIN briskers.customers c
      ON c.business_id=d.business_id AND c.id=d.customer_id
    LEFT JOIN briskers.jobs j
      ON j.business_id=d.business_id AND j.id=d.job_id
    LEFT JOIN briskers.payment_methods pm
      ON pm.business_id=p_business_id AND pm.id=r.payment_method_id
    WHERE r.receipt_amount>0
  ), page AS (
    SELECT * FROM enriched
    ORDER BY receipt_date DESC, receipt_time DESC, receipt_id DESC
    LIMIT GREATEST(1, LEAST(COALESCE(p_limit,250),500))
    OFFSET GREATEST(COALESCE(p_offset,0),0)
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'receipt_id', receipt_id,
      'transaction_id', transaction_id,
      'operation_id', operation_id,
      'invoice_id', invoice_id,
      'document_number', document_number,
      'customer_name', customer_name,
      'job_number', job_number,
      'payment_method', payment_method,
      'amount', receipt_amount,
      'invoice_total', invoice_total,
      'covered_amount', covered_amount,
      'transaction_date', receipt_date,
      'received_at', receipt_time,
      'receipt_state', receipt_state,
      'coverage', CASE WHEN covered_amount + 0.005 >= invoice_total
                       THEN 'paid' ELSE 'partial' END
    ) ORDER BY receipt_date DESC,receipt_time DESC,receipt_id DESC), '[]'::jsonb)
    INTO v_result
  FROM page;
  RETURN v_result;
END
$function$
;
COMMIT;
