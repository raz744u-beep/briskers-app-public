-- Faster restartable expense synchronization; no business records are changed.
-- Keep the existing offset RPC for older client versions.
CREATE OR REPLACE FUNCTION public.briskers_linked_expenses_after_v1(
  p_business_id uuid,
  p_after_allocation_id uuid DEFAULT NULL,
  p_limit integer DEFAULT 500
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_result jsonb;
BEGIN
  PERFORM briskers.require_permission(p_business_id, 'expenses.read');
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'allocation_id', ea.id, 'id', ft.id, 'transaction_id', ft.id,
    'job_id', ea.job_id, 'job_number', j.job_number,
    'document_id', ea.document_id, 'document_number', d.document_number,
    'scope', CASE WHEN ea.document_id IS NULL THEN 'job' ELSE 'invoice' END,
    'direction', 'expense', 'kind', ft.kind,
    'amount', ea.amount, 'signed_amount', -ea.amount,
    'transaction_date', ft.transaction_date,
    'counterparty', coalesce(v.name, ft.payee_text, 'Expense'),
    'vendor', coalesce(v.name, ft.payee_text, 'Expense'),
    'category', fc.name, 'remarks', coalesce(ea.memo, ft.remarks, ''),
    'memo', coalesce(ea.memo, ft.remarks, '')
  ) ORDER BY ea.id), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT a.*
    FROM briskers.expense_allocations a
    JOIN briskers.financial_transactions t
      ON t.business_id = a.business_id AND t.id = a.transaction_id
    WHERE a.business_id = p_business_id
      AND (p_after_allocation_id IS NULL OR a.id > p_after_allocation_id)
      AND t.status = 'posted' AND t.amount < 0
    ORDER BY a.id
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 500), 1), 500)
  ) ea
  JOIN briskers.financial_transactions ft
    ON ft.business_id = ea.business_id AND ft.id = ea.transaction_id
  LEFT JOIN briskers.vendors v
    ON v.business_id = ft.business_id AND v.id = ft.vendor_id
  LEFT JOIN briskers.financial_categories fc
    ON fc.business_id = ea.business_id AND fc.id = ea.category_id
  LEFT JOIN briskers.jobs j
    ON j.business_id = ea.business_id AND j.id = ea.job_id
  LEFT JOIN briskers.sales_documents d
    ON d.business_id = ea.business_id AND d.id = ea.document_id;
  RETURN v_result;
END
$function$;
REVOKE ALL ON FUNCTION public.briskers_linked_expenses_after_v1(uuid,uuid,integer)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.briskers_linked_expenses_after_v1(uuid,uuid,integer)
  TO authenticated;

-- Include authoritative edit-lock metadata in the existing document index
-- so unchanged historical detail snapshots can be refreshed without fetching
-- thousands of full line-item details. Existing v3 permission checks remain.
CREATE OR REPLACE FUNCTION public.briskers_list_documents_v4(
  p_business_id uuid, p_kind text
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_base jsonb; v_result jsonb;
BEGIN
  v_base := public.briskers_list_documents_v3(p_business_id, p_kind);
  SELECT COALESCE(
    jsonb_agg(
      item || jsonb_build_object(
        'future_date_flag',
          COALESCE(d.source_metadata->>'intentional_future_date','false')='true',
        'origin', d.origin,
        'closed_at', d.closed_at,
        'legacy_read_only', d.origin IS DISTINCT FROM 'native',
        'legacy_editable',
          (d.kind = 'invoice'
           AND d.origin IS DISTINCT FROM 'native'
           AND d.source_system = 'mobilebiz'
           AND d.closed_at IS NULL AND d.status IN ('draft','issued')
           AND COALESCE(NULLIF(item->>'paid_amount','')::numeric,0) = 0
           AND COALESCE(NULLIF(item->>'pending_payment','')::numeric,0) = 0
           AND NOT EXISTS (
             SELECT 1 FROM briskers.payment_allocations pa
             WHERE pa.business_id=d.business_id AND pa.document_id=d.id
           )
           AND NOT EXISTS (
             SELECT 1 FROM briskers.invoice_pending_payments pp
             WHERE pp.business_id=d.business_id AND pp.invoice_id=d.id
           ))
      )
      ORDER BY nullif(item->>'document_date','')::date DESC NULLS LAST,
               d.created_at DESC, d.id
    ),'[]'::jsonb)
  INTO v_result
  FROM jsonb_array_elements(v_base) item
  JOIN briskers.sales_documents d
    ON d.business_id = p_business_id AND d.id = (item->>'id')::uuid;
  RETURN v_result;
END
$function$;
