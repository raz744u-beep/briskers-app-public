-- Atomic owner-controlled Job cleanup. Estimates survive deletion.
-- Preview is read-only; commit RPC locks and validates again.
CREATE OR REPLACE FUNCTION public.briskers_job_delete_plan(
  p_business_id uuid, p_job_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_job briskers.jobs;
  v_block text;
  v_invoices jsonb := '[]'::jsonb;
  v_estimates jsonb := '[]'::jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT briskers.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Owner access required' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_job FROM briskers.jobs
  WHERE business_id=p_business_id AND id=p_job_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Job not found' USING ERRCODE='P0002';
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',d.id,'number',d.document_number,'total',d.total_amount,
    'status',d.status) ORDER BY d.created_at,d.id),'[]'::jsonb)
  INTO v_invoices FROM briskers.sales_documents d
  WHERE d.business_id=p_business_id AND d.job_id=p_job_id
    AND d.kind='invoice';

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',d.id,'number',d.document_number,'status',d.status)
    ORDER BY d.created_at,d.id),'[]'::jsonb)
  INTO v_estimates FROM briskers.sales_documents d
  WHERE d.business_id=p_business_id AND d.job_id=p_job_id
    AND d.kind='estimate';

  IF EXISTS(
    SELECT 1 FROM briskers.sales_documents d
    WHERE d.business_id=p_business_id AND d.job_id=p_job_id
      AND d.kind NOT IN ('invoice','estimate')
  ) THEN
    v_block:='Job has other protected documents';
  ELSIF EXISTS(
    SELECT 1 FROM briskers.sales_documents d
    WHERE d.business_id=p_business_id AND d.job_id=p_job_id
      AND d.kind='invoice'
      AND (d.origin<>'native' OR d.closed_at IS NOT NULL
           OR d.status IN ('void','closed','paid')
           OR d.extended_warranty=true
           OR d.warranty_company_id IS NOT NULL)
  ) THEN
    v_block:='A linked invoice is closed, imported or otherwise protected';
  ELSIF EXISTS(
    SELECT 1 FROM briskers.sales_documents d
    WHERE d.business_id=p_business_id AND d.job_id=p_job_id
      AND d.kind='invoice'
      AND (EXISTS(SELECT 1 FROM briskers.invoice_pending_payments x
         WHERE x.business_id=d.business_id AND x.invoice_id=d.id)
      OR EXISTS(SELECT 1 FROM briskers.payment_allocations x
         WHERE x.business_id=d.business_id AND x.document_id=d.id)
      OR EXISTS(SELECT 1 FROM briskers.expense_allocations x
         WHERE x.business_id=d.business_id AND x.document_id=d.id)
      OR EXISTS(SELECT 1 FROM briskers.document_revisions x
         WHERE x.business_id=d.business_id AND x.document_id=d.id)
      OR EXISTS(SELECT 1 FROM briskers.document_attachments x
         WHERE x.business_id=d.business_id AND x.document_id=d.id)
      OR EXISTS(SELECT 1 FROM briskers.authorizations x
         WHERE x.business_id=d.business_id AND x.document_id=d.id)
      OR EXISTS(SELECT 1 FROM briskers.customer_notes x
         WHERE x.business_id=d.business_id
           AND (x.found_document_id=d.id OR x.resolved_document_id=d.id))
      OR EXISTS(SELECT 1 FROM briskers.sales_documents x
         WHERE x.business_id=d.business_id AND x.credited_invoice_id=d.id))
  ) THEN
    v_block:='A linked invoice has payments, expenses or protected history';
  ELSIF EXISTS(
    SELECT 1 FROM briskers.job_visits v
    WHERE v.business_id=p_business_id AND v.job_id=p_job_id
      AND (v.visit_number<>1 OR v.work_summary IS NOT NULL
           OR v.closed_at IS NOT NULL OR coalesce(v.planned_hours,0)<>0)
  ) OR (SELECT count(*) FROM briskers.job_visits v
        WHERE v.business_id=p_business_id AND v.job_id=p_job_id)>1 THEN
    v_block:='Job contains service visit or work history';
  ELSIF EXISTS(
    SELECT 1 FROM briskers.job_status_events e
    WHERE e.business_id=p_business_id AND e.job_id=p_job_id
      AND (e.from_status IS NOT NULL
           AND NOT(e.from_status='open' AND e.to_status='pending_approval'))
  ) THEN
    v_block:='Job has status change history';
  ELSIF EXISTS(
    SELECT 1 FROM briskers.job_pre_inspections x
    WHERE x.business_id=p_business_id AND x.job_id=p_job_id
  ) OR EXISTS(
    SELECT 1 FROM briskers.expense_allocations x
    WHERE x.business_id=p_business_id AND x.job_id=p_job_id
  ) OR EXISTS(
    SELECT 1 FROM briskers.job_assignments x
    WHERE x.business_id=p_business_id AND x.job_id=p_job_id
  ) OR EXISTS(
    SELECT 1 FROM briskers.job_assignment_requests x
    WHERE x.business_id=p_business_id AND x.job_id=p_job_id
  ) OR EXISTS(
    SELECT 1 FROM briskers.job_attachments x
    WHERE x.business_id=p_business_id AND x.job_id=p_job_id
  ) OR EXISTS(
    SELECT 1 FROM briskers.job_internal_notes x
    WHERE x.business_id=p_business_id AND x.job_id=p_job_id
  ) OR EXISTS(
    SELECT 1 FROM briskers.appointments x
    WHERE x.business_id=p_business_id AND x.job_id=p_job_id
  ) OR EXISTS(
    SELECT 1 FROM briskers.customer_notes x
    WHERE x.business_id=p_business_id
      AND (x.found_job_id=p_job_id OR x.resolved_job_id=p_job_id
         OR x.repair_job_id=p_job_id)
  ) OR EXISTS(
    SELECT 1 FROM briskers.conversations x
    WHERE x.business_id=p_business_id AND x.job_id=p_job_id
  ) OR EXISTS(
    SELECT 1 FROM briskers.kiosk_registrations x
    WHERE x.job_id=p_job_id
  ) THEN
    v_block:='Job has linked service, financial or communication history';
  END IF;

  RETURN jsonb_build_object(
    'job_id',v_job.id,
    'job_number',v_job.job_number,
    'can_delete',v_block IS NULL,
    'reason',v_block,
    'invoices',v_invoices,
    'estimates_preserved',v_estimates
  );
END
$function$;

-- Single unpaid-invoice deletion optionally includes its Job. The server,
-- not a cached mobile list, determines all linked invoices and protection.
CREATE OR REPLACE FUNCTION public.briskers_delete_invoice_managed_v1(
  p_business_id uuid, p_invoice_id uuid, p_with_job boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
 d briskers.sales_documents;
 v_link record;
 v_result jsonb;
BEGIN
 IF auth.uid() IS NULL OR NOT briskers.is_owner(p_business_id) THEN
   RAISE EXCEPTION 'Owner access required' USING ERRCODE='42501';
 END IF;
 SELECT * INTO d FROM briskers.sales_documents
 WHERE business_id=p_business_id AND id=p_invoice_id AND kind='invoice'
 FOR UPDATE;
 IF NOT FOUND THEN
   RAISE EXCEPTION 'Invoice not found' USING ERRCODE='P0002';
 END IF;
 IF p_with_job THEN
   IF d.job_id IS NULL THEN
     RAISE EXCEPTION 'Invoice is not linked to a Job' USING ERRCODE='55000';
   END IF;
   RETURN public.briskers_delete_job_with_unpaid_v1(p_business_id,d.job_id);
 END IF;
 IF d.origin<>'native' OR d.closed_at IS NOT NULL OR d.status='void'
    OR d.extended_warranty=true THEN
   RAISE EXCEPTION 'Only eligible unpaid native invoices can be deleted'
     USING ERRCODE='55000';
 END IF;
 IF EXISTS(SELECT 1 FROM briskers.invoice_pending_payments p
   WHERE p.business_id=p_business_id AND p.invoice_id=d.id)
   OR EXISTS(SELECT 1 FROM briskers.payment_allocations a
   WHERE a.business_id=p_business_id AND a.document_id=d.id) THEN
   RAISE EXCEPTION 'Invoice has payment activity' USING ERRCODE='55000';
 END IF;
 IF EXISTS(SELECT 1 FROM briskers.document_attachments a
     WHERE a.business_id=p_business_id AND a.document_id=d.id)
   OR EXISTS(SELECT 1 FROM briskers.document_revisions a
     WHERE a.business_id=p_business_id AND a.document_id=d.id)
   OR EXISTS(SELECT 1 FROM briskers.authorizations a
     WHERE a.business_id=p_business_id AND a.document_id=d.id)
   OR EXISTS(SELECT 1 FROM briskers.expense_allocations a
     WHERE a.business_id=p_business_id AND a.document_id=d.id) THEN
   RAISE EXCEPTION 'Invoice has protected attachments or financial history'
     USING ERRCODE='55000';
 END IF;
 -- Clear only conversion linkage, then use the existing audited owner
 -- invoice-deletion function to recycle the number.
 DELETE FROM briskers.sales_document_estimate_links
 WHERE business_id=p_business_id AND invoice_id=d.id;
 PERFORM public.briskers_delete_draft_invoice(p_business_id,d.id);
 -- A removed converted invoice must leave the original estimate reusable.
 FOR v_link IN SELECT id,source_metadata,status
   FROM briskers.sales_documents e
   WHERE e.business_id=p_business_id AND e.id=d.source_estimate_id
   FOR UPDATE
 LOOP
   IF NOT EXISTS(SELECT 1 FROM briskers.sales_documents i
      WHERE i.business_id=p_business_id AND i.source_estimate_id=v_link.id)
      AND NOT EXISTS(SELECT 1 FROM briskers.sales_document_estimate_links l
      WHERE l.business_id=p_business_id AND l.estimate_id=v_link.id) THEN
     UPDATE briskers.sales_documents e
     SET status=CASE
          WHEN e.source_metadata->>'pre_conversion_status'
            IN ('draft','issued','accepted')
          THEN e.source_metadata->>'pre_conversion_status'
          ELSE 'issued' END,
       source_metadata=e.source_metadata-'pre_conversion_status',
       row_version=e.row_version+1,updated_at=clock_timestamp()
     WHERE e.business_id=p_business_id AND e.id=v_link.id;
   END IF;
 END LOOP;
 RETURN jsonb_build_object('deleted_invoice',d.document_number,
                           'job_deleted',false,'job_id',d.job_id);
END
$function$;

-- Atomic cascade with a defensive read-only preview rechecked under lock.
CREATE OR REPLACE FUNCTION public.briskers_delete_job_with_unpaid_v1(
  p_business_id uuid, p_job_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
 v_j briskers.jobs;
 v_plan jsonb;
 v_d briskers.sales_documents;
 v_estimate_id uuid;
 v_result jsonb;
 v_prefix text;
 v_part text;
BEGIN
 IF auth.uid() IS NULL OR NOT briskers.is_owner(p_business_id) THEN
   RAISE EXCEPTION 'Owner access required' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_j FROM briskers.jobs
 WHERE business_id=p_business_id AND id=p_job_id FOR UPDATE;
 IF NOT FOUND THEN
   RAISE EXCEPTION 'Job not found' USING ERRCODE='P0002';
 END IF;
 -- Protect against a concurrent invoice/estimate or payment mutation.
 PERFORM 1 FROM briskers.sales_documents d
 WHERE d.business_id=p_business_id AND d.job_id=p_job_id
 ORDER BY d.id FOR UPDATE;
 v_plan := public.briskers_job_delete_plan(p_business_id,p_job_id);
 IF (v_plan->>'can_delete')::boolean IS DISTINCT FROM true THEN
   RAISE EXCEPTION 'Cannot delete Job: %',v_plan->>'reason'
     USING ERRCODE='55000';
 END IF;

 FOR v_d IN SELECT * FROM briskers.sales_documents d
   WHERE d.business_id=p_business_id AND d.job_id=p_job_id
     AND d.kind='invoice' ORDER BY d.id
 LOOP
   v_estimate_id:=v_d.source_estimate_id;
   DELETE FROM briskers.sales_document_estimate_links l
     WHERE l.business_id=p_business_id AND l.invoice_id=v_d.id;
   PERFORM public.briskers_delete_draft_invoice(p_business_id,v_d.id);
   IF v_estimate_id IS NOT NULL AND
      NOT EXISTS(SELECT 1 FROM briskers.sales_documents i
        WHERE i.business_id=p_business_id AND i.source_estimate_id=v_estimate_id)
      AND NOT EXISTS(SELECT 1 FROM briskers.sales_document_estimate_links l
        WHERE l.business_id=p_business_id AND l.estimate_id=v_estimate_id) THEN
     UPDATE briskers.sales_documents e SET
       status=CASE
          WHEN e.source_metadata->>'pre_conversion_status'
            IN ('draft','issued','accepted')
          THEN e.source_metadata->>'pre_conversion_status'
          ELSE 'issued' END,
       source_metadata=e.source_metadata-'pre_conversion_status',
       row_version=e.row_version+1,updated_at=clock_timestamp()
     WHERE e.business_id=p_business_id AND e.id=v_estimate_id;
   END IF;
 END LOOP;
 -- Quotes survive. They can be converted later without an orphan Job FK.
 UPDATE briskers.sales_documents e
 SET job_id=NULL,row_version=e.row_version+1,updated_at=clock_timestamp()
 WHERE e.business_id=p_business_id AND e.job_id=p_job_id
   AND e.kind='estimate';

 DELETE FROM briskers.job_visits
 WHERE business_id=p_business_id AND job_id=p_job_id;
 DELETE FROM briskers.job_status_events
 WHERE business_id=p_business_id AND job_id=p_job_id;
 DELETE FROM briskers.jobs
 WHERE business_id=p_business_id AND id=p_job_id;

 SELECT prefix INTO v_prefix FROM briskers.document_counters
 WHERE business_id=p_business_id AND document_kind='job';
 IF coalesce(v_prefix,'')='' THEN
   v_part:=v_j.job_number;
 ELSIF left(v_j.job_number,length(v_prefix))=v_prefix THEN
   v_part:=substring(v_j.job_number FROM length(v_prefix)+1);
 END IF;
 IF v_part ~ '^[0-9]+$' THEN
   INSERT INTO briskers.document_number_reuse(
     business_id,document_kind,number_value,prefix
   ) VALUES(p_business_id,'job',v_part::bigint,coalesce(v_prefix,''))
   ON CONFLICT DO NOTHING;
 END IF;
 RETURN v_plan || jsonb_build_object(
    'job_deleted',true,'removed_invoices',v_plan->'invoices',
    'preserved_estimates',v_plan->'estimates_preserved');
END
$function$;

REVOKE ALL ON FUNCTION public.briskers_job_delete_plan(uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.briskers_delete_invoice_managed_v1(uuid,uuid,boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.briskers_delete_job_with_unpaid_v1(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.briskers_job_delete_plan(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.briskers_delete_invoice_managed_v1(uuid,uuid,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.briskers_delete_job_with_unpaid_v1(uuid,uuid) TO authenticated;
