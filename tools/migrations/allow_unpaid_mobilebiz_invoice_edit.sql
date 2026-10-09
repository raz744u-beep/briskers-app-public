-- Permit deliberate activation of unfinished, unpaid MobileBiz invoices.
-- Provenance is retained in source_system/source_reference/source_metadata
-- and the entire pre-edit document is archived as a revision.
CREATE OR REPLACE FUNCTION public.briskers_enable_open_imported_invoice_edit(
  p_business_id uuid,
  p_document_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  d briskers.sales_documents;
  v_line_net numeric;
  v_line_tax numeric;
BEGIN
  PERFORM briskers.require_permission(p_business_id, 'invoices.edit');

  SELECT * INTO d
  FROM briskers.sales_documents
  WHERE business_id = p_business_id AND id = p_document_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invoice not found' USING ERRCODE = 'P0002';
  END IF;

  IF d.kind <> 'invoice' OR d.source_system IS DISTINCT FROM 'mobilebiz' THEN
    RAISE EXCEPTION 'Only imported MobileBiz invoices can be activated'
      USING ERRCODE = '42501';
  END IF;

  IF d.origin = 'native' THEN
    RETURN true;
  END IF;

  IF d.closed_at IS NOT NULL OR d.status NOT IN ('draft','issued') THEN
    RAISE EXCEPTION 'Completed, closed or void invoices cannot be activated'
      USING ERRCODE = '42501';
  END IF;

  IF EXISTS (
    SELECT 1 FROM briskers.payment_allocations a
    WHERE a.business_id = p_business_id
      AND a.document_id = p_document_id
  ) OR EXISTS (
    SELECT 1 FROM briskers.invoice_pending_payments p
    WHERE p.business_id = p_business_id
      AND p.invoice_id = p_document_id
  ) THEN
    RAISE EXCEPTION 'This invoice has payment activity and cannot be activated'
      USING ERRCODE = '42501';
  END IF;

  -- Historical discounts/shipping can have special calculation semantics.
  -- Such documents require individual reconciliation, not silent repricing.
  IF abs(coalesce(d.legacy_discount, 0)) > 0.005
     OR abs(coalesce(d.legacy_shipping, 0)) > 0.005 THEN
    RAISE EXCEPTION 'Legacy adjustments require a reviewed conversion'
      USING ERRCODE = '55000';
  END IF;

  SELECT coalesce(sum(l.net_amount),0), coalesce(sum(l.tax_amount),0)
  INTO v_line_net, v_line_tax
  FROM briskers.sales_document_lines l
  WHERE l.business_id = p_business_id AND l.document_id = p_document_id;

  IF abs(v_line_net - coalesce(d.net_amount,0)) > 0.02
     OR abs(v_line_tax - coalesce(d.tax_amount,0)) > 0.02
     OR abs(v_line_net + v_line_tax - coalesce(d.total_amount,0)) > 0.02 THEN
    RAISE EXCEPTION 'Imported totals need review before editing'
      USING ERRCODE = '55000';
  END IF;

  PERFORM briskers.capture_document_revision(
    p_business_id, p_document_id, 'MobileBiz invoice activated for editing'
  );

  -- Native editing RPCs will subsequently use normal price recalculation.
  -- The source metadata and original revision remain intact.
  UPDATE briskers.sales_documents
  SET origin = 'native',
      updated_at = clock_timestamp(),
      row_version = row_version + 1
  WHERE business_id = p_business_id AND id = p_document_id;

  RETURN true;
END
$function$;

REVOKE ALL ON FUNCTION public.briskers_enable_open_imported_invoice_edit(uuid,uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.briskers_enable_open_imported_invoice_edit(uuid,uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.briskers_document_detail_v3(
  p_business_id uuid, p_document_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v jsonb;
  v_origin text;
  v_closed timestamptz;
  v_source text;
  v_status text;
BEGIN
  v := public.briskers_document_detail_v2(p_business_id,p_document_id);
  SELECT d.origin, d.closed_at, d.source_system, d.status
  INTO v_origin, v_closed, v_source, v_status
  FROM briskers.sales_documents d
  WHERE d.business_id = p_business_id AND d.id = p_document_id;

  RETURN v || jsonb_build_object(
    'origin', v_origin,
    'closed_at', v_closed,
    'legacy_read_only', v_origin IS DISTINCT FROM 'native',
    'legacy_editable',
      v_origin IS DISTINCT FROM 'native'
      AND v_source = 'mobilebiz'
      AND v_closed IS NULL
      AND v_status IN ('draft','issued')
      AND coalesce(nullif(v->>'paid_amount','')::numeric,0) = 0
      AND coalesce(nullif(v->>'pending_payment','')::numeric,0) = 0
      AND NOT EXISTS (
        SELECT 1 FROM briskers.payment_allocations a
        WHERE a.business_id = p_business_id AND a.document_id = p_document_id
      )
      AND NOT EXISTS (
        SELECT 1 FROM briskers.invoice_pending_payments p
        WHERE p.business_id = p_business_id AND p.invoice_id = p_document_id
      )
  );
END
$function$;
