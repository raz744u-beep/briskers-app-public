-- A single atomic operation for offline invoice drafts.
-- Retries with the same operation UUID return the existing invoice rather
-- than duplicating the invoice or any line items.
CREATE UNIQUE INDEX IF NOT EXISTS briskers_unique_offline_invoice_operation
ON briskers.sales_documents (
  business_id, (source_metadata->>'offline_operation_id')
)
WHERE kind='invoice' AND source_metadata ? 'offline_operation_id';

CREATE OR REPLACE FUNCTION public.briskers_sync_offline_quick_invoice_v1(
  p_business_id uuid,
  p_customer_id uuid,
  p_vehicle_id uuid,
  p_operation_id uuid,
  p_document_date date,
  p_lines jsonb DEFAULT '[]'::jsonb,
  p_memo text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_document uuid;
  v_number text;
  v_line jsonb;
  v_pos integer:=0;
  v_quantity numeric;
  v_price numeric;
  v_tax numeric;
  v_line_kind text;
  v_name text;
  v_item_id uuid;
BEGIN
  PERFORM briskers.require_permission(p_business_id,'invoices.create');
  IF p_operation_id IS NULL THEN
    RAISE EXCEPTION 'Offline invoice operation ID is required'
      USING ERRCODE='22023';
  END IF;
  IF p_lines IS NULL OR jsonb_typeof(p_lines)<>'array'
     OR jsonb_array_length(p_lines)>250 THEN
    RAISE EXCEPTION 'Invalid offline invoice items' USING ERRCODE='22023';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtext(p_business_id::text||':offline-invoice:'||p_operation_id::text)
  );
  SELECT id INTO v_document FROM briskers.sales_documents
  WHERE business_id=p_business_id AND kind='invoice'
    AND source_metadata->>'offline_operation_id'=p_operation_id::text
  LIMIT 1;
  IF FOUND THEN
    RETURN v_document;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM briskers.customers c
    WHERE c.business_id=p_business_id AND c.id=p_customer_id AND c.active
  ) THEN
    RAISE EXCEPTION 'Customer not found or inactive' USING ERRCODE='P0002';
  END IF;
  IF p_vehicle_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM briskers.vehicle_customers vc
    JOIN briskers.vehicles v ON v.business_id=vc.business_id
      AND v.id=vc.vehicle_id
    WHERE vc.business_id=p_business_id AND vc.customer_id=p_customer_id
      AND vc.vehicle_id=p_vehicle_id AND v.active
      AND (vc.valid_until IS NULL OR vc.valid_until>=current_date)
  ) THEN
    RAISE EXCEPTION 'Vehicle is not linked to the customer'
      USING ERRCODE='23514';
  END IF;

  v_number:=briskers.next_number(p_business_id,'invoice');
  INSERT INTO briskers.sales_documents(
    business_id,kind,customer_id,vehicle_id,document_number,
    document_date,memo,source_metadata,created_by
  ) VALUES (
    p_business_id,'invoice',p_customer_id,p_vehicle_id,v_number,
    coalesce(p_document_date,current_date),nullif(btrim(coalesce(p_memo,'')),''),
    jsonb_build_object('offline_operation_id',p_operation_id::text),
    auth.uid()
  ) RETURNING id INTO v_document;

  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    v_pos:=v_pos+1;
    v_name:=btrim(coalesce(v_line->>'name',''));
    v_line_kind:=coalesce(v_line->>'line_kind','item');
    v_quantity:=nullif(v_line->>'quantity','')::numeric;
    v_price:=nullif(v_line->>'unit_price','')::numeric;
    v_tax:=coalesce(nullif(v_line->>'tax_rate','')::numeric,0);
    v_item_id:=nullif(v_line->>'item_id','')::uuid;
    IF v_name='' OR v_line_kind NOT IN ('item','labor','shipping','supply','other')
       OR v_quantity IS NULL OR v_quantity<=0 OR v_quantity>1000000
       OR v_price IS NULL OR v_price<0
       OR v_tax<0 OR v_tax>1 THEN
      RAISE EXCEPTION 'Invalid item at position %',v_pos USING ERRCODE='22023';
    END IF;

    INSERT INTO briskers.sales_document_lines(
      business_id,document_id,position,item_id,line_kind,name,description,
      quantity,unit_price,tax_rate,net_amount,tax_amount,created_by
    ) VALUES (
      p_business_id,v_document,v_pos,v_item_id,v_line_kind,v_name,
      nullif(v_line->>'description',''),v_quantity,v_price,v_tax,
      round(v_quantity*v_price,2),round(round(v_quantity*v_price,2)*v_tax,2),
      auth.uid()
    );
  END LOOP;
  IF v_pos>0 THEN
    PERFORM briskers.recalculate_native_document(p_business_id,v_document);
  END IF;
  RETURN v_document;
END
$function$;
REVOKE ALL ON FUNCTION public.briskers_sync_offline_quick_invoice_v1(
  uuid,uuid,uuid,uuid,date,jsonb,text
) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.briskers_sync_offline_quick_invoice_v1(
  uuid,uuid,uuid,uuid,date,jsonb,text
) TO authenticated;
