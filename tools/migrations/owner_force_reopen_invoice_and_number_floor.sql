-- Owner-authorized historical invoice correction. Preserve every original value
-- and all payments in document_revisions; never modify posted allocations.
CREATE OR REPLACE FUNCTION public.briskers_owner_force_reopen_invoice(
  p_business_id uuid,
  p_document_id uuid,
  p_expected_version bigint,
  p_reason text
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  d briskers.sales_documents;
  v_net numeric;
  v_tax numeric;
BEGIN
  IF auth.uid() IS NULL OR NOT briskers.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Only the shop owner can force reopen an invoice'
      USING ERRCODE='42501';
  END IF;
  IF length(btrim(coalesce(p_reason,''))) < 10 THEN
    RAISE EXCEPTION 'Enter a reason of at least 10 characters'
      USING ERRCODE='22023';
  END IF;
  SELECT * INTO d FROM briskers.sales_documents
  WHERE business_id=p_business_id AND id=p_document_id FOR UPDATE;
  IF NOT FOUND OR d.kind <> 'invoice' THEN
    RAISE EXCEPTION 'Invoice not found' USING ERRCODE='P0002';
  END IF;
  IF d.row_version <> p_expected_version THEN
    RAISE EXCEPTION 'Invoice has changed; reload before reopening'
      USING ERRCODE='40001';
  END IF;
  IF d.status='void' THEN
    RAISE EXCEPTION 'Voided invoices require a separate reviewed correction'
      USING ERRCODE='42501';
  END IF;
  IF d.origin='native' AND d.closed_at IS NULL THEN
    RAISE EXCEPTION 'Invoice is already open and editable' USING ERRCODE='22023';
  END IF;
  IF coalesce(d.legacy_discount,0) <> 0
     OR coalesce(d.legacy_shipping,0) <> 0 THEN
    RAISE EXCEPTION 'Legacy discount or shipping requires individual reconciliation'
      USING ERRCODE='55000';
  END IF;
  SELECT coalesce(sum(l.net_amount),0),coalesce(sum(l.tax_amount),0)
  INTO v_net,v_tax
  FROM briskers.sales_document_lines l
  WHERE l.business_id=p_business_id AND l.document_id=p_document_id;
  IF abs(v_net-coalesce(d.net_amount,0))>0.05
     OR abs(v_tax-coalesce(d.tax_amount,0))>0.05
     OR abs(v_net+v_tax-coalesce(d.total_amount,0))>0.05 THEN
    RAISE EXCEPTION 'Historical invoice amounts do not reconcile. Review before editing.'
      USING ERRCODE='55000';
  END IF;
  IF EXISTS(
    SELECT 1 FROM briskers.sales_documents x
    WHERE x.business_id=p_business_id AND x.kind='invoice'
      AND x.id<>d.id AND x.document_number=d.document_number
      AND x.origin='native'
  ) THEN
    RAISE EXCEPTION 'An editable invoice already uses this historical number'
      USING ERRCODE='23505';
  END IF;
  PERFORM briskers.capture_document_revision(
    p_business_id,d.id,'Owner forced reopening: '||btrim(p_reason)
  );
  UPDATE briskers.sales_documents
  SET origin='native',closed_at=NULL,status='issued',
      source_metadata=coalesce(d.source_metadata,'{}'::jsonb)
          || jsonb_build_object(
               'owner_reopened_at',clock_timestamp(),
               'owner_reopen_reason',btrim(p_reason),
               'prior_origin',d.origin,
               'prior_closed_at',d.closed_at
             ),
      updated_at=clock_timestamp(),row_version=row_version+1
  WHERE business_id=p_business_id AND id=p_document_id;
  RETURN true;
END $function$;
REVOKE ALL ON FUNCTION public.briskers_owner_force_reopen_invoice(uuid,uuid,bigint,text)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.briskers_owner_force_reopen_invoice(uuid,uuid,bigint,text)
  TO authenticated;

-- Prevent owner numbering controls from setting the next invoice number below
-- the highest existing historical invoice. A new invoice must follow 6331+.
CREATE OR REPLACE FUNCTION briskers.owner_set_next_number(
  b uuid,k text,requested_next bigint
) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_existing bigint;
BEGIN
  IF auth.uid() IS NULL OR NOT briskers.is_owner(b) THEN
    RAISE EXCEPTION 'Only the business owner may change numbering'
      USING ERRCODE='42501';
  END IF;
  IF k NOT IN ('invoice','estimate','job') THEN
    RAISE EXCEPTION 'Unsupported number type: %',k USING ERRCODE='22023';
  END IF;
  IF requested_next IS NULL OR requested_next<1 OR requested_next>999999999 THEN
    RAISE EXCEPTION 'Next number must be between 1 and 999999999'
      USING ERRCODE='22023';
  END IF;
  IF k='invoice' THEN
    SELECT max(d.document_number::bigint) INTO v_existing
    FROM briskers.sales_documents d
    WHERE d.business_id=b AND d.kind='invoice'
      AND d.document_number ~ '^[0-9]{1,9}$';
    IF requested_next <= coalesce(v_existing,0) THEN
      RAISE EXCEPTION 'Next invoice number must be greater than the highest existing invoice (%)',
        v_existing USING ERRCODE='22023';
    END IF;
  END IF;
  UPDATE briskers.document_counters
  SET next_number=requested_next,updated_at=clock_timestamp()
  WHERE business_id=b AND document_kind=k;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Numbering is not initialized for %',k
      USING ERRCODE='55000';
  END IF;
  RETURN requested_next;
END $function$;
