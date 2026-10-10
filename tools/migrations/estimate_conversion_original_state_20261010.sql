-- Save pre-conversion estimate state for exact status and number restoration.
-- All existing conversion permission, line-copy and paid-invoice guards remain.
CREATE OR REPLACE FUNCTION public.briskers_add_estimate_to_invoice_v1(p_business_id uuid, p_estimate_id uuid, p_invoice_id uuid, p_operation_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  e briskers.sales_documents;
  i briskers.sales_documents;
  v_result jsonb;
  v_existing_invoice uuid;
  v_existing_number text;
  v_pos integer;
  v_num text;
  v_has_paid boolean;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode='42501';
  end if;

  if nullif(btrim(coalesce(p_operation_id,'')),'') is null
     or length(p_operation_id)>160 then
    raise exception 'Invalid operation ID' using errcode='22023';
  end if;

  select o.result into v_result
  from briskers.sync_applied_operations o
  where o.business_id=p_business_id
    and o.operation_id=p_operation_id;
  if v_result is not null then
    return v_result;
  end if;

  perform briskers.require_permission(p_business_id,'estimates.edit');
  perform briskers.require_permission(p_business_id,'invoices.edit');

  select * into e
  from briskers.sales_documents
  where business_id=p_business_id and id=p_estimate_id
  for update;

  if not found or e.kind<>'estimate' then
    raise exception 'Estimate not found' using errcode='P0002';
  end if;
  if e.origin<>'native'
     or e.status in ('void','declined','expired') then
    raise exception 'Estimate cannot be added to an invoice' using errcode='55000';
  end if;

  select x.id, x.document_number
  into v_existing_invoice, v_existing_number
  from briskers.sales_documents x
  where x.business_id=p_business_id
    and x.kind='invoice'
    and x.source_estimate_id=p_estimate_id
    and x.status<>'void'
  limit 1;

  if v_existing_invoice is null then
    select l.invoice_id, x.document_number
    into v_existing_invoice, v_existing_number
    from briskers.sales_document_estimate_links l
    join briskers.sales_documents x
      on x.business_id=l.business_id
     and x.id=l.invoice_id
     and x.status<>'void'
    where l.business_id=p_business_id
      and l.estimate_id=p_estimate_id
    limit 1;
  end if;

  if v_existing_invoice is not null then
    if v_existing_invoice = p_invoice_id then
      v_result := jsonb_build_object(
        'status','already_applied',
        'invoice_id',v_existing_invoice,
        'invoice_number',v_existing_number
      );
      insert into briskers.sync_applied_operations(
        business_id,operation_id,entity_type,result
      ) values(
        p_business_id,p_operation_id,'estimate_add_to_invoice',v_result
      )
      on conflict (business_id,operation_id) do nothing;
      return v_result;
    end if;
    raise exception 'Estimate has already been converted or added to another invoice'
      using errcode='55000';
  end if;

  select * into i
  from briskers.sales_documents
  where business_id=p_business_id and id=p_invoice_id
  for update;

  if not found or i.kind<>'invoice' then
    raise exception 'Invoice not found' using errcode='P0002';
  end if;
  if i.origin<>'native' or i.status='void' or i.closed_at is not null then
    raise exception 'Only an open native invoice can receive estimate items'
      using errcode='55000';
  end if;
  if i.customer_id<>e.customer_id then
    raise exception 'Estimate and invoice must belong to the same customer'
      using errcode='23514';
  end if;
  if i.currency_code<>e.currency_code then
    raise exception 'Estimate and invoice currencies do not match'
      using errcode='23514';
  end if;

  select exists(
    select 1
    from briskers.payment_allocations a
    join briskers.financial_transactions t
      on t.business_id=a.business_id and t.id=a.transaction_id
    where a.business_id=p_business_id
      and a.document_id=i.id
      and t.status='posted'
  ) into v_has_paid;

  if v_has_paid and not briskers.is_owner(p_business_id) then
    raise exception 'Only the owner can add work to an invoice after payment is finalized'
      using errcode='42501';
  end if;

  if v_has_paid then
    perform briskers.capture_document_revision(
      p_business_id,i.id,'Owner added converted estimate to invoice'
    );
  end if;

  if e.document_number is null then
    v_num:=briskers.next_number(p_business_id,'estimate');
    update briskers.sales_documents
    set document_number=v_num,
        document_date=coalesce(document_date,current_date),
        issued_at=coalesce(issued_at,clock_timestamp()),
        published_at=coalesce(published_at,clock_timestamp()),
        status='accepted',
        source_metadata=coalesce(source_metadata,'{}'::jsonb) ||
          jsonb_build_object('pre_conversion_status',e.status,
                             'pre_conversion_had_number',false),
        updated_at=clock_timestamp(),
        row_version=row_version+1
    where business_id=p_business_id and id=p_estimate_id;
  else
    update briskers.sales_documents
    set status='accepted',
        source_metadata=coalesce(source_metadata,'{}'::jsonb) ||
          jsonb_build_object('pre_conversion_status',e.status,
                             'pre_conversion_had_number',true),
        updated_at=clock_timestamp(),
        row_version=row_version+1
    where business_id=p_business_id and id=p_estimate_id;
  end if;

  select coalesce(max(position),0)
  into v_pos
  from briskers.sales_document_lines
  where business_id=p_business_id
    and document_id=p_invoice_id;

  insert into briskers.sales_document_lines(
    business_id,document_id,position,item_id,line_kind,name,description,
    quantity,unit_price,pricing_unit,tax_rate,net_amount,tax_amount,
    discount_method,discount_timing,discount_value,part_number,
    imported_unit_price,price_verification_status,dealer_list_price,
    price_source_name,price_source_url,price_checked_at,
    price_verification_note,price_verification_confidence,created_by
  )
  select
    l.business_id,p_invoice_id,v_pos + row_number() over(order by l.position,l.id),
    l.item_id,l.line_kind,l.name,l.description,
    l.quantity,l.unit_price,l.pricing_unit,l.tax_rate,l.net_amount,l.tax_amount,
    l.discount_method,l.discount_timing,l.discount_value,l.part_number,
    l.imported_unit_price,l.price_verification_status,l.dealer_list_price,
    l.price_source_name,l.price_source_url,l.price_checked_at,
    l.price_verification_note,l.price_verification_confidence,auth.uid()
  from briskers.sales_document_lines l
  where l.business_id=p_business_id
    and l.document_id=p_estimate_id
  order by l.position,l.id;

  if not found then
    raise exception 'Estimate has no items' using errcode='55000';
  end if;

  perform briskers.recalculate_native_document(p_business_id,p_invoice_id);

  update briskers.sales_documents
  set updated_at=clock_timestamp(),
      row_version=row_version+1
  where business_id=p_business_id
    and id=p_invoice_id;

  insert into briskers.sales_document_estimate_links(
    business_id,estimate_id,invoice_id,operation_id,created_by
  ) values(
    p_business_id,p_estimate_id,p_invoice_id,p_operation_id,auth.uid()
  );

  select jsonb_build_object(
    'status','applied',
    'invoice_id',d.id,
    'invoice_number',d.document_number,
    'invoice_total',d.total_amount,
    'invoice_row_version',d.row_version,
    'estimate_id',p_estimate_id
  )
  into v_result
  from briskers.sales_documents d
  where d.business_id=p_business_id and d.id=p_invoice_id;

  insert into briskers.sync_applied_operations(
    business_id,operation_id,entity_type,result
  ) values(
    p_business_id,p_operation_id,'estimate_add_to_invoice',v_result
  )
  on conflict (business_id,operation_id) do nothing;

  return v_result;
end
$function$;


CREATE OR REPLACE FUNCTION public.briskers_convert_estimate(p_business_id uuid, p_estimate_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  e briskers.sales_documents;
  inv uuid;
  v_num text;
  v_invoice_num text;
begin
  perform briskers.require_permission(p_business_id,'invoices.create');

  select * into e
  from briskers.sales_documents
  where business_id=p_business_id and id=p_estimate_id
  for update;

  if not found or e.kind<>'estimate' or e.status in ('void','declined','expired') then
    raise exception 'Estimate cannot be converted' using errcode='55000';
  end if;
  if e.origin<>'native' then
    raise exception 'Historical estimate conversion requires a reviewed import first'
      using errcode='55000';
  end if;

  select id into inv
  from briskers.sales_documents
  where business_id=p_business_id
    and source_estimate_id=p_estimate_id
    and kind='invoice'
    and status<>'void';

  if inv is not null then
    return inv;
  end if;

  if e.document_number is null then
    v_num:=briskers.next_number(p_business_id,'estimate');
    update briskers.sales_documents
    set document_number=v_num,
        document_date=coalesce(document_date,current_date),
        issued_at=coalesce(issued_at,clock_timestamp()),
        published_at=coalesce(published_at,clock_timestamp()),
        status='accepted',
        source_metadata=coalesce(source_metadata,'{}'::jsonb) ||
          jsonb_build_object('pre_conversion_status',e.status,
                             'pre_conversion_had_number',false),
        updated_at=clock_timestamp(),
        row_version=row_version+1
    where business_id=p_business_id and id=p_estimate_id;
  else
    update briskers.sales_documents
    set status='accepted',
        source_metadata=coalesce(source_metadata,'{}'::jsonb) ||
          jsonb_build_object('pre_conversion_status',e.status,
                             'pre_conversion_had_number',true),
        updated_at=clock_timestamp(),
        row_version=row_version+1
    where business_id=p_business_id and id=p_estimate_id;
  end if;

  v_invoice_num:=briskers.next_number(p_business_id,'invoice');

  insert into briskers.sales_documents(
    business_id,kind,customer_id,job_id,source_estimate_id,
    document_number,document_date,
    net_amount,tax_amount,currency_code,authorization_number,
    claim_number,signature_required,memo,created_by
  )
  values(
    p_business_id,'invoice',e.customer_id,e.job_id,e.id,
    v_invoice_num,current_date,
    e.net_amount,e.tax_amount,e.currency_code,e.authorization_number,
    e.claim_number,e.signature_required,e.memo,auth.uid()
  )
  returning id into inv;

  insert into briskers.sales_document_lines(
    business_id,document_id,position,item_id,line_kind,name,description,
    quantity,unit_price,pricing_unit,tax_rate,net_amount,tax_amount,created_by
  )
  select
    business_id,inv,position,item_id,line_kind,name,description,
    quantity,unit_price,pricing_unit,tax_rate,net_amount,tax_amount,auth.uid()
  from briskers.sales_document_lines
  where business_id=p_business_id and document_id=p_estimate_id;

  return inv;
end $function$;


