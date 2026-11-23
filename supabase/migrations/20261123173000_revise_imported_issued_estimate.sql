CREATE FUNCTION public.briskers_owner_enable_issued_estimate_revision(
  p_business_id uuid,
  p_document_id uuid,
  p_expected_version bigint
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  estimate briskers.sales_documents;
  line_net numeric;
  line_tax numeric;
BEGIN
  IF auth.uid() IS NULL OR NOT briskers.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Only the owner can revise an imported estimate' USING ERRCODE='42501';
  END IF;
  PERFORM briskers.require_permission(p_business_id, 'estimates.edit');

  SELECT * INTO estimate FROM briskers.sales_documents
  WHERE business_id=p_business_id AND id=p_document_id AND kind='estimate'
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Estimate not found' USING ERRCODE='P0002';
  END IF;
  IF estimate.row_version IS DISTINCT FROM p_expected_version THEN
    RAISE EXCEPTION 'Estimate changed. Refresh it before revising.' USING ERRCODE='40001';
  END IF;
  IF estimate.status IS DISTINCT FROM 'issued' OR estimate.closed_at IS NOT NULL
     OR nullif(btrim(estimate.document_number::text), '') IS NULL
     OR EXISTS (
       SELECT 1 FROM briskers.sales_documents invoice
       WHERE invoice.business_id=p_business_id AND invoice.kind='invoice'
         AND invoice.source_estimate_id=p_document_id
     ) OR EXISTS (
       SELECT 1 FROM briskers.sales_document_estimate_links link
       WHERE link.business_id=p_business_id AND link.estimate_id=p_document_id
     ) THEN
    RAISE EXCEPTION 'Only an open issued estimate with no invoice link can be revised'
      USING ERRCODE='42501';
  END IF;
  IF estimate.origin = 'native' THEN
    RETURN true;
  END IF;

  SELECT coalesce(sum(net_amount),0), coalesce(sum(tax_amount),0)
  INTO line_net, line_tax FROM briskers.sales_document_lines
  WHERE business_id=p_business_id AND document_id=p_document_id;
  IF coalesce(estimate.legacy_discount,0) <> 0 OR coalesce(estimate.legacy_shipping,0) <> 0
     OR abs(line_net - coalesce(estimate.net_amount,0)) > 0.02
     OR abs(line_tax - coalesce(estimate.tax_amount,0)) > 0.02
     OR abs(line_net + line_tax - coalesce(estimate.total_amount,0)) > 0.02 THEN
    RAISE EXCEPTION 'Imported estimate amounts need review before editing'
      USING ERRCODE='55000';
  END IF;

  PERFORM briskers.capture_document_revision(
    p_business_id, p_document_id, 'Owner enabled revision of issued estimate'
  );
  UPDATE briskers.sales_documents
  SET origin='native', updated_at=clock_timestamp(), row_version=row_version+1
  WHERE business_id=p_business_id AND id=p_document_id;
  RETURN true;
END
$function$;

REVOKE ALL ON FUNCTION public.briskers_owner_enable_issued_estimate_revision(uuid,uuid,bigint)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.briskers_owner_enable_issued_estimate_revision(uuid,uuid,bigint)
  TO authenticated;
