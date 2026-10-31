-- DRAFT ONLY: do not deploy until isolated DB regression tests and explicit authorization.
-- Scoped to invoices created by the v2 recovery entrypoint. Existing documents
-- keep their prior per-line rounding because they lack this metadata marker.
-- Replacements preserve the original function body's permission and RLS checks.
BEGIN;
CREATE OR REPLACE FUNCTION briskers.recalculate_native_document(b uuid, d uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  x briskers.sales_documents;
  base_net numeric := 0;
  base_tax numeric := 0;
  current_net numeric := 0;
  current_tax numeric := 0;
  discount_amount numeric := 0;
  discount_tax numeric := 0;
  gross_now numeric := 0;
  r record;
begin
  select * into x
  from briskers.sales_documents
  where business_id=b and id=d
  for update;

  if not found or x.origin<>'native' then
    raise exception 'Historical totals require a reviewed correction, not automatic repricing'
      using errcode='55000';
  end if;

  -- The actual tax_amount column is numeric(18,2): writing six decimals
  -- would silently round each line, re-introducing Gloria's +$0.01.
  -- Preserve ordinary invoices exactly as before, then allocate rounded
  -- whole-invoice tax cents only for this explicitly opted-in recovery source.
  update briskers.sales_document_lines l
  set net_amount=round(l.quantity*l.unit_price,2),
      tax_amount=round(round(l.quantity*l.unit_price,2)*l.tax_rate,2)
  where l.business_id=b
    and l.document_id=d
    and l.line_kind<>'discount';

  if x.source_metadata->>'offline_tax_rounding'='invoice_total_unrounded' then
    with fractional_tax as (
      select l.id,
             floor(l.net_amount*l.tax_rate*100)::bigint as base_cents,
             row_number() over (
               order by (l.net_amount*l.tax_rate*100
                         -floor(l.net_amount*l.tax_rate*100)) desc,
                        l.position, l.id
             ) as penny_rank,
             round(sum(l.net_amount*l.tax_rate) over (),2)*100
               as target_cents,
             sum(floor(l.net_amount*l.tax_rate*100)::bigint) over ()
               as base_total_cents
      from briskers.sales_document_lines l
      where l.business_id=b
        and l.document_id=d
        and l.line_kind<>'discount'
    ),
    allocated as (
      select id,
             (base_cents + case
               when penny_rank <= target_cents-base_total_cents then 1
               else 0
             end)::numeric / 100 as tax_cents_exact
      from fractional_tax
    )
    update briskers.sales_document_lines l
       set tax_amount=a.tax_cents_exact
    from allocated a
    where l.business_id=b and l.id=a.id;
  end if;

  select coalesce(sum(l.net_amount),0),
         coalesce(sum(l.tax_amount),0)
  into base_net,base_tax
  from briskers.sales_document_lines l
  where l.business_id=b
    and l.document_id=d
    and l.line_kind<>'discount';

  current_net := base_net;
  current_tax := base_tax;

  for r in
    select *
    from briskers.sales_document_lines
    where business_id=b
      and document_id=d
      and line_kind='discount'
      and discount_timing='before_tax'
    order by position
  loop
    if current_net <= 0 then
      discount_amount := 0;
      discount_tax := 0;
    else
      discount_amount := case
        when r.discount_method='percent'
          then round(current_net * coalesce(r.discount_value,0) / 100,2)
        else least(round(coalesce(r.discount_value,0),2),current_net)
      end;
      discount_amount := greatest(0,least(discount_amount,current_net));
      discount_tax := case
        when current_net=0 then 0
        else round(current_tax * discount_amount / current_net,2)
      end;
    end if;

    update briskers.sales_document_lines l
    set quantity=1,
        unit_price=0,
        tax_rate=0,
        net_amount=-discount_amount,
        tax_amount=-discount_tax,
        updated_at=clock_timestamp(),
        row_version=l.row_version+1
    where l.business_id=b and l.id=r.id;

    current_net := current_net-discount_amount;
    current_tax := current_tax-discount_tax;
  end loop;

  for r in
    select *
    from briskers.sales_document_lines
    where business_id=b
      and document_id=d
      and line_kind='discount'
      and discount_timing='after_tax'
    order by position
  loop
    gross_now := greatest(current_net+current_tax,0);
    discount_amount := case
      when r.discount_method='percent'
        then round(gross_now * coalesce(r.discount_value,0) / 100,2)
      else least(round(coalesce(r.discount_value,0),2),gross_now)
    end;
    discount_amount := greatest(0,least(discount_amount,gross_now));

    update briskers.sales_document_lines l
    set quantity=1,
        unit_price=0,
        tax_rate=0,
        net_amount=-discount_amount,
        tax_amount=0,
        updated_at=clock_timestamp(),
        row_version=l.row_version+1
    where l.business_id=b and l.id=r.id;

    current_net := current_net-discount_amount;
  end loop;

  update briskers.sales_documents
  set net_amount=greatest(round(current_net,2),0),
      tax_amount=greatest(round(current_tax,2),0)
  where business_id=b and id=d;
end $function$
;
CREATE OR REPLACE FUNCTION public.briskers_sync_offline_quick_invoice_v2(p_business_id uuid, p_customer_id uuid, p_vehicle_id uuid, p_operation_id uuid, p_document_date date, p_lines jsonb, p_memo text, p_expected_net_cents bigint, p_expected_tax_cents bigint)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_document uuid;
  v_number text;
  v_job_id uuid;
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
  PERFORM briskers.require_permission(p_business_id,'jobs.create');
  -- Recovery bypasses standard per-line rounding only for an Owner.
  -- Permissions alone are insufficient: a Secretary could have both
  -- invoices.create and jobs.create in the normal operational role.
  IF NOT EXISTS (
    SELECT 1 FROM briskers.memberships m
    WHERE m.business_id=p_business_id
      AND m.user_id=auth.uid()
      AND m.active
      AND m.role_code='owner'
  ) THEN
    RAISE EXCEPTION 'Only the Owner may recover exact-total offline invoices'
      USING ERRCODE='42501';
  END IF;
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
    IF EXISTS (
      SELECT 1 FROM briskers.sales_documents
      WHERE business_id=p_business_id AND id=v_document
        AND customer_id=p_customer_id
        AND vehicle_id IS NOT DISTINCT FROM p_vehicle_id
        AND source_metadata->>'offline_tax_rounding'='invoice_total_unrounded'
        AND source_metadata->>'offline_payload_signature'=md5(
          p_lines::text||'|'||coalesce(p_memo,'')||'|'||coalesce(p_document_date::text,'<null>')
        )
        AND round(net_amount*100)::bigint=p_expected_net_cents
        AND round(tax_amount*100)::bigint=p_expected_tax_cents
    ) THEN RETURN v_document; END IF;
    RAISE EXCEPTION 'Original offline invoice exists with different verified amounts or payload'
      USING ERRCODE='23505';
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
  -- Job, initial visit, and invoice commit atomically. Replays of an
  -- operation ID return the existing document before this point.
  v_job_id := public.briskers_create_job(
    p_business_id, p_customer_id, p_vehicle_id,
    'Invoice #' || v_number,
    'Created automatically from offline invoice #' || v_number
  );
  INSERT INTO briskers.sales_documents(
    business_id,kind,customer_id,vehicle_id,job_id,document_number,
    document_date,memo,source_metadata,created_by
  ) VALUES (
    p_business_id,'invoice',p_customer_id,p_vehicle_id,v_job_id,v_number,
    coalesce(p_document_date,current_date),nullif(btrim(coalesce(p_memo,'')),''),
    jsonb_build_object(
      'offline_operation_id',p_operation_id::text,
      'offline_tax_rounding','invoice_total_unrounded',
      'offline_payload_signature',md5(
        p_lines::text||'|'||coalesce(p_memo,'')||'|'||coalesce(p_document_date::text,'<null>')
      )
    ),
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
  IF NOT EXISTS (
    SELECT 1 FROM briskers.sales_documents
    WHERE business_id=p_business_id AND id=v_document
      AND round(net_amount*100)::bigint=p_expected_net_cents
      AND round(tax_amount*100)::bigint=p_expected_tax_cents
  ) THEN
    RAISE EXCEPTION 'Offline invoice totals differ from verified local source; rolling back'
      USING ERRCODE='22023';
  END IF;
  RETURN v_document;
END
$function$
;
REVOKE ALL ON FUNCTION public.briskers_sync_offline_quick_invoice_v2(
  uuid,uuid,uuid,uuid,date,jsonb,text,bigint,bigint
) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.briskers_sync_offline_quick_invoice_v2(
  uuid,uuid,uuid,uuid,date,jsonb,text,bigint,bigint
) TO authenticated;
COMMIT;
