-- Every posted expense/refund requires category allocations to balance,
-- including ordinary unlinked manual expenses.
-- Preserve the current authorized create transaction RPC and replace only
-- its allocation condition, which previously skipped unlinked expenses.
DO $fix$
DECLARE fn text;
BEGIN
 SELECT pg_get_functiondef(p.oid) INTO fn
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='briskers_create_manual_transaction'
 ORDER BY p.oid LIMIT 1;
 IF fn IS NULL OR position(
   'if resolved_job_id is not null or p_document_id is not null then'
   in lower(fn))=0 THEN
   RAISE EXCEPTION 'Unexpected RPC definition; allocation fix aborted';
 END IF;
 fn := replace(fn,
   'if resolved_job_id is not null or p_document_id is not null then',
   'if tx_kind in (''supplier_expense'', ''other_expense'', ''supplier_refund'') then');
 EXECUTE fn;
END $fix$;
