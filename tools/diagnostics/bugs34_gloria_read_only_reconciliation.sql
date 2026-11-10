-- Bugs 34: READ-ONLY reconciliation diagnostic for one invoice.
-- Replace the invoice UUID with a separately verified value for other cases.
-- Does not mutate records or change Force Offline.
WITH target AS (
  SELECT id, business_id, job_id, total_amount, status, closed_at
  FROM briskers.sales_documents
  WHERE id = '4bc125a0-7954-4036-82f2-4650847463f3'::uuid
),
pending AS (
  SELECT p.id, p.amount, p.payment_date, k.operation_id
  FROM briskers.invoice_pending_payments p
  JOIN target d ON d.id = p.invoice_id AND d.business_id = p.business_id
  LEFT JOIN briskers.invoice_payment_operation_keys k
    ON k.business_id = p.business_id AND k.invoice_id = p.invoice_id
   AND k.pending_payment_id = p.id
),
posted AS (
  SELECT a.id allocation_id, a.transaction_id, a.gross_amount, t.status,
         t.idempotency_key
  FROM briskers.payment_allocations a
  JOIN target d ON d.id = a.document_id AND d.business_id = a.business_id
  JOIN briskers.financial_transactions t
    ON t.id = a.transaction_id AND t.business_id = a.business_id
)
SELECT 'invoice' AS source, d.id::text AS record_id,
       d.total_amount::text AS amount, d.status AS state,
       d.closed_at::text AS detail
FROM target d
UNION ALL
SELECT 'pending_payment', p.id::text, p.amount::text, 'pending',
       'operation=' || coalesce(p.operation_id::text, 'UNMAPPED')
FROM pending p
UNION ALL
SELECT 'allocation', p.transaction_id::text, p.gross_amount::text,
       p.status, 'idempotency=' || coalesce(p.idempotency_key::text, 'NULL')
FROM posted p;
