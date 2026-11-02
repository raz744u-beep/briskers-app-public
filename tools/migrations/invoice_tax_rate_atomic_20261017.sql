-- Owner-approved invoice-level Tax pencil. This defines a guarded RPC only:
-- No existing invoice, line, tax setting, catalog or payment is modified by deployment.
-- Preserve zero-rate exempt lines; reject mixed positive/custom rates and discounts
-- until a reviewed tax-provenance mechanism can distinguish them safely.
create or replace function public.briskers_update_invoice_tax_rate_v1(
  p_business_id uuid,
  p_invoice_id uuid,
  p_expected_version bigint,
  p_old_rate numeric,
  p_new_rate numeric
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  d briskers.sales_documents;
  v_positive_rates integer;
  v_old_rate numeric;
  v_lines integer;
  v_pending numeric;
  v_revision uuid;
  v_total numeric;
  v_tax numeric;
begin
  perform briskers.require_permission(p_business_id, 'invoices.edit');
  if p_new_rate is null or p_new_rate <= 0 or p_new_rate > 1
    or p_old_rate is null or p_old_rate <= 0 or p_old_rate > 1 then
    raise exception 'Invalid tax rate' using errcode='22023';
  end if;
  if p_expected_version is null then
    raise exception 'Document version required' using errcode='22023';
  end if;
  select * into d from briskers.sales_documents
    where business_id=p_business_id and id=p_invoice_id
    for update;
  if not found or d.kind <> 'invoice' then
    raise exception 'Invoice not found' using errcode='P0002';
  end if;
  if d.origin <> 'native' or d.status in ('void','closed','paid')
    or d.closed_at is not null then
    raise exception 'Historical, closed or paid invoice cannot be repriced'
      using errcode='55000';
  end if;
  if d.row_version <> p_expected_version then
    raise exception 'Invoice changed; reload before editing tax'
      using errcode='40001';
  end if;
  if exists(
    select 1 from briskers.payment_allocations a
    where a.business_id=p_business_id and a.document_id=p_invoice_id
  ) then
    raise exception 'Posted or allocated payments prevent tax editing'
      using errcode='55000';
  end if;
  -- Lock all lines while validating; another editor cannot race this batch.
  perform 1 from briskers.sales_document_lines l
    where l.business_id=p_business_id and l.document_id=p_invoice_id
    order by l.id for update;
  if exists (
    select 1 from briskers.sales_document_lines l
    where l.business_id=p_business_id and l.document_id=p_invoice_id
      and (l.line_kind='discount' or l.tax_rate<0 or l.tax_rate>1)
  ) then
    raise exception 'Review discounted or mixed-tax invoices individually'
      using errcode='55000';
  end if;
  select count(distinct tax_rate), max(tax_rate), count(*)
    into v_positive_rates, v_old_rate, v_lines
    from briskers.sales_document_lines l
    where l.business_id=p_business_id and l.document_id=p_invoice_id
      and l.line_kind <> 'discount' and l.tax_rate > 0;
  if v_lines=0 or v_positive_rates <> 1 or v_old_rate <> p_old_rate then
    raise exception 'Tax provenance ambiguous; verify existing taxable lines'
      using errcode='55000';
  end if;
  select coalesce(sum(p.amount),0) into v_pending
    from briskers.invoice_pending_payments p
    where p.business_id=p_business_id and p.invoice_id=p_invoice_id;
  v_revision := briskers.capture_document_revision(
    p_business_id,p_invoice_id,'Owner invoice-wide sales tax correction');
  update briskers.sales_document_lines l
    set tax_rate=p_new_rate,
        tax_amount=round(round(l.quantity*l.unit_price,2)*p_new_rate,2),
        updated_at=clock_timestamp(),
        row_version=l.row_version+1
    where l.business_id=p_business_id
      and l.document_id=p_invoice_id
      and l.line_kind<>'discount'
      and l.tax_rate>0;
  perform briskers.recalculate_native_document(p_business_id,p_invoice_id);
  update briskers.sales_documents x
    set total_amount=greatest(round(x.net_amount+x.tax_amount,2),0),
        updated_at=clock_timestamp(),
        row_version=x.row_version+1
    where x.business_id=p_business_id and x.id=p_invoice_id
    returning x.total_amount,x.tax_amount into v_total,v_tax;
  if v_pending > v_total + 0.005 then
    raise exception 'Pending payments exceed corrected total; reconcile before editing'
      using errcode='23514';
  end if;
  return jsonb_build_object(
    'invoice_id',p_invoice_id,
    'revision_id',v_revision,
    'tax_rate',p_new_rate,
    'tax_amount',v_tax,
    'total_amount',v_total,
    'changed_lines',v_lines
  );
end;
$function$;

revoke all on function public.briskers_update_invoice_tax_rate_v1(uuid,uuid,bigint,numeric,numeric)
  from public,anon;
grant execute on function public.briskers_update_invoice_tax_rate_v1(uuid,uuid,bigint,numeric,numeric)
  to authenticated;
