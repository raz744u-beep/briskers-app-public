-- A standalone estimate has a customer, optional vehicle and no Job.
-- Conversion to invoice creates a Job atomically when none is linked.
CREATE OR REPLACE FUNCTION public.briskers_create_standalone_estimate_v1(
 p_business_id uuid, p_customer_id uuid, p_vehicle_id uuid DEFAULT NULL,
 p_id uuid DEFAULT gen_random_uuid()
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign-in required' USING ERRCODE='42501'; END IF;
 PERFORM briskers.require_permission(p_business_id,'estimates.create');
 IF NOT EXISTS(SELECT 1 FROM briskers.customers c
   WHERE c.business_id=p_business_id AND c.id=p_customer_id) THEN
   RAISE EXCEPTION 'Customer not found' USING ERRCODE='P0002';
 END IF;
 IF p_vehicle_id IS NOT NULL AND NOT EXISTS(
   SELECT 1 FROM briskers.vehicle_customers r
   WHERE r.business_id=p_business_id AND r.vehicle_id=p_vehicle_id
     AND r.customer_id=p_customer_id
     AND (r.valid_until IS NULL OR r.valid_until>=current_date)) THEN
   RAISE EXCEPTION 'Vehicle does not belong to customer' USING ERRCODE='23514';
 END IF;
 INSERT INTO briskers.sales_documents(
   id,business_id,kind,customer_id,vehicle_id,job_id,
   document_date,source_metadata,created_by
 ) VALUES(
   p_id,p_business_id,'estimate',p_customer_id,p_vehicle_id,NULL,
   current_date,jsonb_build_object('standalone_estimate',true),auth.uid()
 ) ON CONFLICT (id) DO NOTHING;
 IF NOT EXISTS(SELECT 1 FROM briskers.sales_documents d
   WHERE d.id=p_id AND d.business_id=p_business_id AND d.kind='estimate'
   AND d.customer_id=p_customer_id AND d.job_id IS NULL) THEN
   RAISE EXCEPTION 'Conflicting estimate ID' USING ERRCODE='23505';
 END IF;
 RETURN p_id;
END
$function$;

CREATE OR REPLACE FUNCTION public.briskers_sync_offline_standalone_estimate_v1(
 p_business_id uuid,
 p_customer_id uuid,
 p_vehicle_id uuid,
 p_operation_id uuid,
 p_document_date date,
 p_lines jsonb,
 p_memo text
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
 v_line jsonb;
 v_index integer := 0;
 v_count integer;
 v_name text;
 v_kind text;
 v_qty numeric;
 v_price numeric;
 v_tax numeric;
BEGIN
 IF auth.uid() IS NULL THEN
   RAISE EXCEPTION 'Sign-in required' USING ERRCODE='42501';
 END IF;
 PERFORM briskers.require_permission(p_business_id,'estimates.create');
 PERFORM briskers.require_permission(p_business_id,'estimates.edit');
 IF p_operation_id IS NULL OR p_customer_id IS NULL THEN
   RAISE EXCEPTION 'Missing estimate sync identity' USING ERRCODE='22023';
 END IF;
 IF jsonb_typeof(p_lines) IS DISTINCT FROM 'array' THEN
   RAISE EXCEPTION 'Estimate lines must be a list' USING ERRCODE='22023';
 END IF;
 v_count:=jsonb_array_length(p_lines);
 IF v_count>250 THEN
   RAISE EXCEPTION 'Too many estimate lines' USING ERRCODE='22023';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtext(p_business_id::text||':estimate:'||p_operation_id::text));
 IF EXISTS(SELECT 1 FROM briskers.sales_documents d
   WHERE d.id=p_operation_id AND d.business_id=p_business_id
     AND d.kind='estimate' AND d.customer_id=p_customer_id
     AND d.source_metadata->>'offline_operation_id'=p_operation_id::text) THEN
   RETURN p_operation_id;
 END IF;
 IF EXISTS(SELECT 1 FROM briskers.sales_documents d WHERE d.id=p_operation_id) THEN
   RAISE EXCEPTION 'Estimate sync ID belongs to a different record' USING ERRCODE='23505';
 END IF;
 PERFORM public.briskers_create_standalone_estimate_v1(
   p_business_id,p_customer_id,p_vehicle_id,p_operation_id);
 UPDATE briskers.sales_documents d SET
   document_date=coalesce(p_document_date,current_date),
   memo=p_memo,
   source_metadata=d.source_metadata || jsonb_build_object(
     'offline_operation_id',p_operation_id::text),
   updated_at=clock_timestamp()
 WHERE d.business_id=p_business_id AND d.id=p_operation_id;

 FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
   v_index:=v_index+1;
   v_name:=nullif(btrim(coalesce(v_line->>'name','')),'');
   v_kind:=coalesce(nullif(v_line->>'line_kind',''),'item');
   v_qty:=coalesce(nullif(v_line->>'quantity','')::numeric,1);
   v_price:=coalesce(nullif(v_line->>'unit_price','')::numeric,0);
   v_tax:=coalesce(nullif(v_line->>'tax_rate','')::numeric,0);
   IF v_name IS NULL OR v_kind NOT IN ('item','labor','supply','other','discount')
      OR v_qty=0 OR v_price<0 OR v_tax<0 OR v_tax>1 THEN
     RAISE EXCEPTION 'Invalid estimate line %',v_index USING ERRCODE='22023';
   END IF;
   INSERT INTO briskers.sales_document_lines(
     business_id,document_id,position,item_id,line_kind,
     name,description,quantity,unit_price,pricing_unit,tax_rate,
     net_amount,tax_amount,created_by
   ) VALUES(
     p_business_id,p_operation_id,v_index,
     CASE WHEN nullif(v_line->>'item_id','') IS NULL THEN NULL
       ELSE (v_line->>'item_id')::uuid END,
     v_kind,v_name,v_line->>'description',v_qty,v_price,
     nullif(v_line->>'pricing_unit',''),v_tax,
     v_qty*v_price,v_qty*v_price*v_tax,auth.uid()
   );
 END LOOP;
 PERFORM briskers.recalculate_native_document(p_business_id,p_operation_id);
 UPDATE briskers.sales_documents SET
   row_version=row_version+1,updated_at=clock_timestamp()
 WHERE business_id=p_business_id AND id=p_operation_id;
 RETURN p_operation_id;
END
$function$;

REVOKE ALL ON FUNCTION public.briskers_create_standalone_estimate_v1(uuid,uuid,uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.briskers_sync_offline_standalone_estimate_v1(uuid,uuid,uuid,uuid,date,jsonb,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.briskers_create_standalone_estimate_v1(uuid,uuid,uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.briskers_sync_offline_standalone_estimate_v1(uuid,uuid,uuid,uuid,date,jsonb,text) TO authenticated;
