-- Catalog replacement keeps the same invoice line and payroll/task identity.
-- Ordinary edits continue using v2, so older clients remain compatible.
CREATE OR REPLACE FUNCTION public.briskers_replace_document_line_catalog_v1(
  p_business_id uuid, p_line_id uuid, p_expected_version bigint,
  p_name text, p_quantity numeric, p_unit_price numeric, p_tax_rate numeric,
  p_description text, p_line_kind text, p_item_id uuid
) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  old_line briskers.sales_document_lines;
  document briskers.sales_documents;
  catalog briskers.catalog_items;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sign-in required' USING ERRCODE='42501';
  END IF;
  SELECT * INTO old_line FROM briskers.sales_document_lines
    WHERE business_id=p_business_id AND id=p_line_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Line not found' USING ERRCODE='P0002';
  END IF;
  SELECT * INTO document FROM briskers.sales_documents
    WHERE business_id=p_business_id AND id=old_line.document_id FOR UPDATE;
  PERFORM briskers.require_permission(p_business_id,
    CASE WHEN document.kind='estimate' THEN 'estimates.edit' ELSE 'invoices.edit' END);
  IF document.closed_at IS NOT NULL
      OR document.status IN ('closed','void')
      OR (document.kind='estimate' AND EXISTS(SELECT 1 FROM briskers.sales_documents i
        WHERE i.business_id=p_business_id AND i.source_estimate_id=document.id AND i.kind='invoice')) THEN
    RAISE EXCEPTION 'This document is read-only' USING ERRCODE='22023';
  END IF;
  SELECT * INTO catalog FROM briskers.catalog_items
    WHERE business_id=p_business_id AND id=p_item_id AND active FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Choose an active catalog item for this shop' USING ERRCODE='22023';
  END IF;
  IF (old_line.line_kind IN ('labor','labour') OR lower(btrim(old_line.name)) IN ('labor','labour'))
      AND p_line_kind IS DISTINCT FROM 'labor' THEN
    RAISE EXCEPTION 'Keep labor allocations on a labor line' USING ERRCODE='22023';
  END IF;
  -- Reuse all version, amount, permission and total validation in one transaction.
  PERFORM public.briskers_update_document_line_v2(p_business_id,p_line_id,
    p_expected_version,p_name,p_quantity,p_unit_price,p_tax_rate,p_description,p_line_kind);
  UPDATE briskers.sales_document_lines SET item_id=catalog.id,
      pricing_unit=catalog.pricing_unit
    WHERE business_id=p_business_id AND id=p_line_id;
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.briskers_replace_document_line_catalog_v1(uuid,uuid,bigint,text,numeric,numeric,numeric,text,text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.briskers_replace_document_line_catalog_v1(uuid,uuid,bigint,text,numeric,numeric,numeric,text,text,uuid) TO authenticated;
NOTIFY pgrst, 'reload schema';
