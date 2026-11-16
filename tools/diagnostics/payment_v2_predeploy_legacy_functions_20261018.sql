-- Briskers payment v2 rollback reference, saved before approved migration.
-- NEVER execute automatically. Restoration would require separate review,
-- especially if newer payments with payment_date have been posted.
-- Active database legacy routine definitions, captured at deployment.

CREATE OR REPLACE FUNCTION public.briskers_finalize_pending_invoice_payment(p_business_id uuid, p_invoice_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  d briskers.sales_documents;
  p record;
  v_tx uuid;
  v_last_tx uuid;
begin
  perform briskers.require_permission(p_business_id,'payments.create');

  select * into d
  from briskers.sales_documents
  where business_id=p_business_id and id=p_invoice_id
  for update;

  if not found or d.kind<>'invoice' then
    raise exception 'Invoice not found' using errcode='P0002';
  end if;

  if not exists(
    select 1 from briskers.invoice_pending_payments x
    where x.business_id=p_business_id and x.invoice_id=p_invoice_id
  ) then
    raise exception 'No pending payment was entered for this invoice'
      using errcode='P0002';
  end if;

  if d.document_number is null or d.status='draft' then
    perform public.briskers_issue_document(
      p_business_id,p_invoice_id,d.row_version,current_date
    );
  end if;

  for p in
    select *
    from briskers.invoice_pending_payments
    where business_id=p_business_id and invoice_id=p_invoice_id
    order by entered_at,id
    for update
  loop
    v_tx := public.briskers_record_payment(
      p_business_id,p_invoice_id,p.account_id,p.amount,
      gen_random_uuid(),current_date,p.payment_method_id
    );
    v_last_tx := v_tx;

    delete from briskers.invoice_pending_payments
    where business_id=p_business_id and id=p.id;
  end loop;

  return v_last_tx;
end
$function$;

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
      p.entered_at::date AS receipt_date,
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
$function$;