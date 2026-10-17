-- Read-only, tenant/permission-scoped invoice receipt inventory.
-- Do not treat pending receipts as posted accounting income.
CREATE OR REPLACE FUNCTION public.briskers_invoice_receipts_v1(
  p_business_id uuid,
  p_limit integer DEFAULT 250,
  p_offset integer DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
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
      NULL::uuid AS operation_id,
      p.invoice_id,
      p.amount AS receipt_amount,
      p.entered_at AS receipt_time,
      p.entered_at::date AS receipt_date,
      p.payment_method_id
    FROM briskers.invoice_pending_payments p
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

REVOKE ALL ON FUNCTION public.briskers_invoice_receipts_v1(uuid,integer,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.briskers_invoice_receipts_v1(uuid,integer,integer) TO authenticated;
