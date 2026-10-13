-- Preserve unlinked expense allocation when a secretary/owner edits amount.
-- This guards the existing public.briskers_update_manual_transaction RPC.
DO $fix$
DECLARE fn text;
BEGIN
 SELECT pg_get_functiondef(p.oid) INTO fn
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='briskers_update_manual_transaction'
 ORDER BY p.oid LIMIT 1;
 IF fn IS NULL OR position(
    'if resolved_job_id is not null or p_document_id is not null then'
    in lower(fn)) = 0 THEN
    RAISE EXCEPTION 'Unexpected expense-update RPC; aborting';
 END IF;
 fn := replace(fn,
    'if resolved_job_id is not null or p_document_id is not null then',
    'if tx_kind in (''supplier_expense'', ''other_expense'', ''supplier_refund'') then');
 EXECUTE fn;
END $fix$;
