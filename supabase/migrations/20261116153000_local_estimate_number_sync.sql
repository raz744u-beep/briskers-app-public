-- UUID-based numbers match those assigned offline. Keep every existing number.
CREATE FUNCTION briskers.fill_native_estimate_number_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  IF NEW.kind = 'estimate' AND NEW.origin = 'native'
      AND lower(btrim(coalesce(NEW.document_number,''))) IN ('','pending sync') THEN
    NEW.document_number := 'EST-' || upper(replace(NEW.id::text,'-',''));
  END IF;
  RETURN NEW;
END
$$;

CREATE TRIGGER fill_native_estimate_number_v1
BEFORE INSERT ON briskers.sales_documents
FOR EACH ROW EXECUTE FUNCTION briskers.fill_native_estimate_number_v1();

CREATE FUNCTION public.briskers_sync_estimate_number_v1(
  p_business_id uuid, p_estimate_id uuid
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sign-in required' USING ERRCODE='42501';
  END IF;
  PERFORM briskers.require_permission(p_business_id,'estimates.edit');
  UPDATE briskers.sales_documents
  SET document_number = 'EST-' || upper(replace(id::text,'-',''))
  WHERE business_id=p_business_id AND id=p_estimate_id AND kind='estimate'
    AND origin='native' AND lower(btrim(coalesce(document_number,''))) IN ('','pending sync');
END
$$;

CREATE FUNCTION public.briskers_sync_offline_job_estimate_v1(
  p_business_id uuid, p_job_id uuid, p_operation_id uuid,
  p_document_date date, p_lines jsonb, p_memo text
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  prior briskers.sales_documents%ROWTYPE;
  v_line jsonb;
  v_index integer := 0;
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
  IF p_operation_id IS NULL OR p_job_id IS NULL OR p_document_date IS NULL
      OR jsonb_typeof(p_lines) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'Invalid estimate sync payload' USING ERRCODE='22023';
  END IF;
  IF jsonb_array_length(p_lines)>250 THEN
    RAISE EXCEPTION 'Too many estimate lines' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext(p_business_id::text||':estimate:'||p_operation_id::text));
  SELECT * INTO prior FROM briskers.sales_documents WHERE id=p_operation_id;
  IF FOUND THEN
    IF prior.business_id=p_business_id AND prior.job_id=p_job_id AND prior.kind='estimate'
        AND prior.source_metadata->>'offline_operation_id'=p_operation_id::text
        AND prior.source_metadata->>'offline_create_hash' =
          md5(jsonb_build_array(p_document_date,p_lines,p_memo)::text) THEN
      RETURN p_operation_id;
    END IF;
    RAISE EXCEPTION 'Estimate sync ID or original payload differs' USING ERRCODE='PT409';
  END IF;

  PERFORM public.briskers_create_estimate(p_business_id,p_job_id,p_operation_id);
  UPDATE briskers.sales_documents SET
    document_date=p_document_date,memo=p_memo,
    source_metadata=coalesce(source_metadata,'{}'::jsonb) || jsonb_build_object(
      'offline_operation_id',p_operation_id::text,
      'offline_create_hash',md5(jsonb_build_array(p_document_date,p_lines,p_memo)::text))
  WHERE business_id=p_business_id AND id=p_operation_id;

  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    v_index:=v_index+1;
    v_name:=nullif(btrim(coalesce(v_line->>'name','')),'');
    v_kind:=coalesce(nullif(v_line->>'line_kind',''),'item');
    v_qty:=coalesce(nullif(v_line->>'quantity','')::numeric,1);
    v_price:=coalesce(nullif(v_line->>'unit_price','')::numeric,0);
    v_tax:=coalesce(nullif(v_line->>'tax_rate','')::numeric,0);
    IF v_name IS NULL OR v_kind NOT IN ('item','labor','supply','other','discount')
        OR v_qty=0 OR v_price<0 OR v_tax NOT BETWEEN 0 AND 1 THEN
      RAISE EXCEPTION 'Invalid estimate line %',v_index USING ERRCODE='22023';
    END IF;
    INSERT INTO briskers.sales_document_lines(
      business_id,document_id,position,item_id,line_kind,name,description,
      quantity,unit_price,pricing_unit,tax_rate,net_amount,tax_amount,created_by
    ) VALUES(
      p_business_id,p_operation_id,v_index,nullif(v_line->>'item_id','')::uuid,
      v_kind,v_name,v_line->>'description',v_qty,v_price,
      nullif(v_line->>'pricing_unit',''),v_tax,v_qty*v_price,v_qty*v_price*v_tax,auth.uid()
    );
  END LOOP;
  PERFORM briskers.recalculate_native_document(p_business_id,p_operation_id);
  UPDATE briskers.sales_documents SET row_version=row_version+1,updated_at=clock_timestamp()
  WHERE business_id=p_business_id AND id=p_operation_id;
  RETURN p_operation_id;
END
$$;

REVOKE ALL ON FUNCTION briskers.fill_native_estimate_number_v1() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.briskers_sync_estimate_number_v1(uuid,uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.briskers_sync_offline_job_estimate_v1(uuid,uuid,uuid,date,jsonb,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.briskers_sync_estimate_number_v1(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.briskers_sync_offline_job_estimate_v1(uuid,uuid,uuid,date,jsonb,text) TO authenticated;
