-- Read-only pull of an already-posted expense. No scheduler or outbox runs.
create or replace function public.briskers_read_recurring_expense_occurrence(
  p_business_id uuid, p_rule_id uuid, p_due_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  occurrence_id uuid;
  result jsonb;
begin
  perform briskers.require_permission(p_business_id, 'expenses.recurring.read');
  perform briskers.require_permission(p_business_id, 'expenses.read');
  select t.id into occurrence_id
  from briskers.recurring_transactions r
  join briskers.financial_transactions t
    on t.business_id = r.business_id and t.recurring_rule_id = r.id
  where r.business_id = p_business_id and r.id = p_rule_id
    and r.direction = 'expense' and t.amount < 0 and t.status = 'posted'
    and t.recurring_occurrence_date = p_due_date;
  if occurrence_id is null then
    return null;
  end if;
  result := public.briskers_transaction_detail(p_business_id, occurrence_id);
  return result || jsonb_build_object(
    'business_id', p_business_id,
    'recurring_rule_id', p_rule_id,
    'recurring_occurrence_date', p_due_date
  );
end;
$$;
revoke all on function public.briskers_read_recurring_expense_occurrence(uuid, uuid, date) from public, anon;
grant execute on function public.briskers_read_recurring_expense_occurrence(uuid, uuid, date) to authenticated;
