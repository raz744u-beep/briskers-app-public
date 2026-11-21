-- Read-only, customer-neutral Owner recovery lookup. No business data writes.
CREATE OR REPLACE FUNCTION briskers.owner_recovery_lookup_v1(
  p_business_id uuid, p_invoice_operation_id text,
  p_customer_operation_id text, p_local_vehicle_id text,
  p_payment_operation_id uuid
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = '' AS $fn$
DECLARE
  d briskers.sales_documents;
  c uuid;
  v uuid;
  k briskers.invoice_payment_operation_keys;
  receipt briskers.invoice_pending_payments;
  detail jsonb;
  initial_visit briskers.job_visits;
BEGIN
  IF auth.uid() IS NULL OR briskers.is_owner(p_business_id) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Owner authentication required' USING ERRCODE='42501';
  END IF;
  IF nullif(p_invoice_operation_id,'') IS NULL OR
     nullif(p_customer_operation_id,'') IS NULL OR
     nullif(p_local_vehicle_id,'') IS NULL OR p_payment_operation_id IS NULL THEN
    RAISE EXCEPTION 'Incomplete operation identities';
  END IF;
  SELECT * INTO STRICT d FROM briskers.sales_documents
    WHERE business_id=p_business_id AND kind='invoice'
      AND source_metadata->>'offline_operation_id'=p_invoice_operation_id;
  SELECT customer_id INTO STRICT c FROM briskers.customer_create_replay
    WHERE business_id=p_business_id AND operation_id=p_customer_operation_id;
  SELECT vehicle_id INTO STRICT v FROM briskers.vehicle_create_replay
    WHERE business_id=p_business_id AND local_vehicle_id=p_local_vehicle_id;
  IF d.customer_id IS DISTINCT FROM c OR d.vehicle_id IS DISTINCT FROM v OR
     d.status <> 'issued' OR d.job_id IS NULL OR NOT EXISTS (
       SELECT 1 FROM briskers.jobs j WHERE j.business_id=p_business_id
       AND j.id=d.job_id AND j.customer_id=c AND j.vehicle_id=v
     ) THEN RAISE EXCEPTION 'Recovery relationship mismatch'; END IF;
  SELECT * INTO STRICT k FROM briskers.invoice_payment_operation_keys
    WHERE business_id=p_business_id AND operation_id=p_payment_operation_id;
  SELECT * INTO STRICT receipt FROM briskers.invoice_pending_payments
    WHERE business_id=p_business_id AND invoice_id=d.id;
  IF k.invoice_id IS DISTINCT FROM d.id OR
     k.pending_payment_id IS DISTINCT FROM receipt.id OR
     k.amount IS DISTINCT FROM receipt.amount OR
     k.method_id IS DISTINCT FROM receipt.payment_method_id OR
     k.payment_date IS DISTINCT FROM receipt.payment_date THEN
    RAISE EXCEPTION 'Original payment identity mismatch';
  END IF;
  SELECT * INTO STRICT initial_visit FROM briskers.job_visits
    WHERE business_id=p_business_id AND job_id=d.job_id AND visit_number=1;
  detail := public.briskers_document_detail_v5(p_business_id,d.id);
  IF jsonb_array_length(detail->'payments') <> 1 THEN
    RAISE EXCEPTION 'Ambiguous server payment count';
  END IF;
  RETURN detail || jsonb_build_object(
    'business_id',p_business_id,'offline_operation_id',p_invoice_operation_id,
    'customer_operation_id',p_customer_operation_id,'local_vehicle_id',p_local_vehicle_id,
    'line_count',jsonb_array_length(detail->'lines'),
    'initial_visit',jsonb_build_object('id',initial_visit.id,'job_id',initial_visit.job_id,
      'visit_number',initial_visit.visit_number,'work_summary',initial_visit.work_summary,
      'closed_at',initial_visit.closed_at),
    'payments',jsonb_build_array((detail->'payments'->0) ||
      jsonb_build_object('invoice_id',d.id,'operation_id',k.operation_id,
        'method_id',k.method_id,'payment_date',k.payment_date))
  );
END $fn$;
REVOKE ALL ON FUNCTION briskers.owner_recovery_lookup_v1(uuid,text,text,text,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION briskers.owner_recovery_lookup_v1(uuid,text,text,text,uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.briskers_owner_recovery_lookup_v1(
  p_business_id uuid, p_invoice_operation_id text,
  p_customer_operation_id text, p_local_vehicle_id text,
  p_payment_operation_id uuid
) RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = '' AS $fn$
  SELECT briskers.owner_recovery_lookup_v1(p_business_id,p_invoice_operation_id,
    p_customer_operation_id,p_local_vehicle_id,p_payment_operation_id);
$fn$;
REVOKE ALL ON FUNCTION public.briskers_owner_recovery_lookup_v1(uuid,text,text,text,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.briskers_owner_recovery_lookup_v1(uuid,text,text,text,uuid) TO authenticated;
