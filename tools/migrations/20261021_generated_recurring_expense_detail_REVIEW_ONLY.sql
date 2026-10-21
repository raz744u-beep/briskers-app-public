-- REVIEW ONLY. Read-only transaction detail presentation fix.
-- Generated recurring expenses link by financial_transactions.recurring_rule_id,
-- whereas the original seeded expense links by source_transaction_id.
-- Prefer the generated record's exact rule, and fall back to the original
-- source link only when it has no recurring_rule_id, preventing duplicates.
-- This modifies no financial transactions, allocations or schedules.
-- Leaves all previous permissions, receipt and invoice projections intact.
CREATE OR REPLACE FUNCTION public.briskers_transaction_detail(p_business_id uuid, p_transaction_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb;
begin
  perform briskers.require_permission(p_business_id,'expenses.read');

  select jsonb_build_object(
    'id',t.id,
    'direction',case when t.amount>0 then 'income' else 'expense' end,
    'kind',t.kind,
    'amount',abs(t.amount),
    'signed_amount',t.amount,
    'date',t.transaction_date,
    'status',t.status,
    'counterparty_id',t.vendor_id,
    'counterparty',coalesce(v.name,t.payee_text,cus.display_name,
      case when t.amount>0 then 'Income' else 'Expense' end),
    'category_id',t.category_id,
    'category',fc.name,
    'category_normal_direction',fc.normal_direction,
    'account_id',t.account_id,
    'account',fa.name,
    'remarks',coalesce(t.remarks,''),
    'job_id',ea.job_id,
    'job_number',j.job_number,
    'job_title',j.title,
    'job_customer_name',job_customer.display_name,
    'document_id',coalesce(ea.document_id,job_invoice.id),
    'document_number',coalesce(d.document_number,job_invoice.document_number),
    'editable',t.status='posted' and t.kind in (
      'supplier_expense','supplier_refund','other_income','other_expense'
    ),
    'deletable',t.status='posted' and t.kind in (
      'supplier_expense','supplier_refund','other_income','other_expense'
    ),
    'recurring_rule',case when rr.id is null then null else jsonb_build_object(
      'id',rr.id,
      'frequency',rr.frequency,
      'interval_count',rr.interval_count,
      'next_date',rr.next_date,
      'end_date',rr.end_date,
      'is_repeating',rr.is_repeating,
      'paused_reason',rr.paused_reason
    ) end,
    'attachments',coalesce(att.items,'[]'::jsonb)
  )
  into result
  from briskers.financial_transactions t
  join briskers.financial_accounts fa
    on fa.business_id=t.business_id and fa.id=t.account_id
  left join briskers.financial_categories fc
    on fc.business_id=t.business_id and fc.id=t.category_id
  left join briskers.vendors v
    on v.business_id=t.business_id and v.id=t.vendor_id
  left join briskers.customers cus
    on cus.business_id=t.business_id and cus.id=t.customer_id
  left join lateral (
    select ea1.job_id,ea1.document_id
    from briskers.expense_allocations ea1
    where ea1.business_id=t.business_id
      and ea1.transaction_id=t.id
    order by ea1.created_at
    limit 1
  ) ea on true
  left join briskers.jobs j
    on j.business_id=t.business_id and j.id=ea.job_id
  left join briskers.customers job_customer
    on job_customer.business_id=j.business_id and job_customer.id=j.customer_id
  left join briskers.sales_documents d
    on d.business_id=t.business_id and d.id=ea.document_id
  left join lateral (
    select d2.id,d2.document_number
    from briskers.sales_documents d2
    where d2.business_id=t.business_id
      and d2.job_id=ea.job_id
      and d2.kind='invoice'
      and d2.status<>'void'
    order by d2.created_at desc
    limit 1
  ) job_invoice on ea.document_id is null
  left join briskers.recurring_transactions rr
    on rr.business_id=t.business_id
   and (
      rr.id=t.recurring_rule_id
      or (
        t.recurring_rule_id is null
        and rr.source_transaction_id=t.id
      )
   )
  left join lateral (
    select coalesce(jsonb_agg(jsonb_build_object(
      'attachment_id',a.id,
      'bucket',a.storage_bucket,
      'key',a.storage_key,
      'filename',a.original_filename,
      'mime_type',a.mime_type,
      'byte_size',a.byte_size
    ) order by a.created_at),'[]'::jsonb) items
    from briskers.expense_attachments x
    join briskers.attachments a
      on a.business_id=x.business_id and a.id=x.attachment_id
    where x.business_id=t.business_id
      and x.transaction_id=t.id
      and a.state='uploaded'
  ) att on true
  where t.business_id=p_business_id
    and t.id=p_transaction_id;

  if result is null then
    raise exception 'Transaction not found' using errcode='P0002';
  end if;

  return result;
end
$function$
;
