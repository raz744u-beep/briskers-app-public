-- Restore original estimate Job link, including NULL for standalone estimates.
CREATE OR REPLACE FUNCTION briskers.restore_estimate_after_invoice_delete(b uuid, eid uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE e briskers.sales_documents;
 v_old text; v_had text; v_prefix text; v_number text;
BEGIN
 SELECT * INTO e FROM briskers.sales_documents
 WHERE business_id=b AND id=eid AND kind='estimate' FOR UPDATE;
 IF NOT FOUND THEN RETURN; END IF;
 IF EXISTS(SELECT 1 FROM briskers.sales_documents d
    WHERE d.business_id=b AND d.kind='invoice' AND d.source_estimate_id=eid)
 OR EXISTS(SELECT 1 FROM briskers.sales_document_estimate_links l
    WHERE l.business_id=b AND l.estimate_id=eid) THEN RETURN; END IF;
 v_old:=e.source_metadata->>'pre_conversion_status';
 v_had:=e.source_metadata->>'pre_conversion_had_number';
 IF v_old IS NULL AND e.status<>'accepted' THEN RETURN; END IF;
 IF v_had='false' AND e.document_number IS NOT NULL THEN
   SELECT prefix INTO v_prefix FROM briskers.document_counters
   WHERE business_id=b AND document_kind='estimate';
   IF coalesce(v_prefix,'')='' THEN
     v_number:=e.document_number;
   ELSIF left(e.document_number,length(v_prefix))=v_prefix THEN
     v_number:=substring(e.document_number FROM length(v_prefix)+1);
   END IF;
   IF v_number ~ '^[0-9]+$' THEN
     INSERT INTO briskers.document_number_reuse(
       business_id,document_kind,number_value,prefix
     ) VALUES(b,'estimate',v_number::bigint,coalesce(v_prefix,''))
     ON CONFLICT DO NOTHING;
   END IF;
 END IF;
 UPDATE briskers.sales_documents d SET
   status=CASE WHEN v_old IN ('draft','issued','accepted')
       THEN v_old ELSE 'issued' END,
   job_id=CASE WHEN d.source_metadata ? 'pre_conversion_job_id'
       THEN nullif(d.source_metadata->>'pre_conversion_job_id','')::uuid
       ELSE d.job_id END,
   document_number=CASE WHEN v_had='false' THEN NULL ELSE d.document_number END,
   issued_at=CASE WHEN v_had='false' THEN NULL ELSE d.issued_at END,
   published_at=CASE WHEN v_had='false' THEN NULL ELSE d.published_at END,
   source_metadata=d.source_metadata
     -'pre_conversion_status'-'pre_conversion_had_number'
     -'pre_conversion_job_id',
   updated_at=clock_timestamp(),row_version=d.row_version+1
 WHERE d.business_id=b AND d.id=eid;
END
$function$;

REVOKE ALL ON FUNCTION briskers.restore_estimate_after_invoice_delete(uuid,uuid) FROM PUBLIC, anon, authenticated;
