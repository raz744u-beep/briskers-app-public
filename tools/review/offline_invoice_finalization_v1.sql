-- New endpoint only. Does not rewrite or reconcile any existing shop records.
CREATE TABLE IF NOT EXISTS briskers.invoice_finalization_operations_v1 (
 business_id uuid NOT NULL, operation_id uuid NOT NULL, invoice_id uuid NOT NULL,
 request jsonb NOT NULL, result jsonb NOT NULL,
 PRIMARY KEY(business_id,operation_id)
);
ALTER TABLE briskers.invoice_finalization_operations_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON briskers.invoice_finalization_operations_v1 FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.briskers_finalize_invoice_once_v1(
 p_business_id uuid,p_invoice_id uuid,p_operation_id uuid,p_request jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET lock_timeout='5s' AS $fn$
DECLARE
 d briskers.sales_documents%ROWTYPE;
 prior briskers.invoice_finalization_operations_v1%ROWTYPE;
 r jsonb; receipt briskers.invoice_pending_payments%ROWTYPE;
 receipt_id uuid; expected_ids uuid[] := '{}';
 paid numeric; result jsonb;
BEGIN
 IF auth.uid() IS NULL OR briskers.is_owner(p_business_id) IS DISTINCT FROM true THEN
  RAISE EXCEPTION 'Owner access required' USING ERRCODE='42501';
 END IF;
 PERFORM briskers.require_permission(p_business_id,'payments.create');
 IF p_operation_id IS NULL OR jsonb_typeof(p_request->'receipts') <> 'array'
    OR jsonb_typeof(p_request->'close') <> 'boolean' THEN
  RAISE EXCEPTION 'Invalid finalization request' USING ERRCODE='22023';
 END IF;
 -- Serialize retries of the same operation, even if a bad client changes invoice.
 PERFORM pg_advisory_xact_lock(hashtextextended(p_business_id::text||p_operation_id::text,0));
 SELECT * INTO prior FROM briskers.invoice_finalization_operations_v1
 WHERE business_id=p_business_id AND operation_id=p_operation_id;
 IF FOUND THEN
  IF prior.invoice_id IS DISTINCT FROM p_invoice_id OR prior.request IS DISTINCT FROM p_request THEN
   RAISE EXCEPTION 'Finalization identity conflict' USING ERRCODE='23505';
  END IF;
  RETURN prior.result;
 END IF;
 SELECT * INTO d FROM briskers.sales_documents
 WHERE business_id=p_business_id AND id=p_invoice_id FOR UPDATE;
 IF NOT FOUND OR d.kind<>'invoice' OR d.status='void' THEN
  RAISE EXCEPTION 'Invoice unavailable for finalization' USING ERRCODE='55000';
 END IF;
 LOCK TABLE briskers.invoice_pending_payments IN SHARE ROW EXCLUSIVE MODE;
 SELECT COALESCE(sum(a.gross_amount),0) INTO paid
 FROM briskers.payment_allocations a JOIN briskers.financial_transactions t
 ON t.business_id=a.business_id AND t.id=a.transaction_id
 WHERE a.business_id=p_business_id AND a.document_id=p_invoice_id AND t.status='posted';
 IF round(d.total_amount*100) IS DISTINCT FROM (p_request->>'total_cents')::numeric
 OR round(paid*100) IS DISTINCT FROM (p_request->>'paid_cents')::numeric THEN
  RAISE EXCEPTION 'Invoice totals changed; review saved finalization' USING ERRCODE='40001';
 END IF;
 PERFORM 1 FROM briskers.invoice_pending_payments
 WHERE business_id=p_business_id AND invoice_id=p_invoice_id ORDER BY id FOR UPDATE;
 FOR r IN SELECT value FROM jsonb_array_elements(p_request->'receipts') LOOP
  receipt_id := NULL;
  IF NULLIF(r->>'operation_id','') IS NOT NULL THEN
   SELECT pending_payment_id INTO receipt_id FROM briskers.invoice_payment_operation_keys
   WHERE business_id=p_business_id AND operation_id=(r->>'operation_id')::uuid
     AND invoice_id=p_invoice_id;
  ELSE
   receipt_id := (r->>'id')::uuid;
  END IF;
  SELECT * INTO receipt FROM briskers.invoice_pending_payments
  WHERE business_id=p_business_id AND invoice_id=p_invoice_id AND id=receipt_id;
  IF NOT FOUND OR receipt_id=ANY(expected_ids)
    OR round(receipt.amount*100) IS DISTINCT FROM (r->>'amount_cents')::numeric
    OR receipt.payment_method_id IS DISTINCT FROM (r->>'method_id')::uuid
    OR COALESCE(receipt.payment_date,receipt.entered_at::date) IS DISTINCT FROM (r->>'payment_date')::date THEN
   RAISE EXCEPTION 'Recorded payment changed; review saved finalization' USING ERRCODE='40001';
  END IF;
  expected_ids := array_append(expected_ids,receipt_id);
 END LOOP;
 IF (SELECT count(*) FROM briskers.invoice_pending_payments
     WHERE business_id=p_business_id AND invoice_id=p_invoice_id) <> cardinality(expected_ids) THEN
  RAISE EXCEPTION 'Recorded payment set changed; review saved finalization' USING ERRCODE='40001';
 END IF;
 IF (p_request->>'close')::boolean THEN
  IF round((paid+COALESCE((SELECT sum(amount) FROM briskers.invoice_pending_payments
      WHERE business_id=p_business_id AND invoice_id=p_invoice_id),0))*100) <> round(d.total_amount*100)
      OR d.total_amount<=0 THEN
   RAISE EXCEPTION 'Invoice must be fully paid before closeout' USING ERRCODE='55000';
  END IF;
  PERFORM public.briskers_close_invoice(p_business_id,p_invoice_id);
 ELSIF cardinality(expected_ids)>0 THEN
  PERFORM public.briskers_finalize_pending_invoice_payment(p_business_id,p_invoice_id);
 ELSE
  RAISE EXCEPTION 'No received payments selected' USING ERRCODE='22023';
 END IF;
 result := jsonb_build_object('operation_id',p_operation_id,'invoice_id',p_invoice_id,
  'finalized',true,'closed',(p_request->>'close')::boolean);
 INSERT INTO briskers.invoice_finalization_operations_v1 VALUES(p_business_id,p_operation_id,p_invoice_id,p_request,result);
 RETURN result;
END;
$fn$;
REVOKE ALL ON FUNCTION public.briskers_finalize_invoice_once_v1(uuid,uuid,uuid,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.briskers_finalize_invoice_once_v1(uuid,uuid,uuid,jsonb) TO authenticated;
