-- REVIEW ONLY. Do not deploy to active Briskers Dev without owner
-- approval to automatically post due financial transactions.
--
-- Cintas 2026-10-21 was due for $105.29; pg_cron run at 12:05Z failed
-- 23514 "Expense allocations must equal the expense/refund amount".
-- Generate the required signed expense allocation in the same transaction;
-- do not disable the deferred money balance constraint.
-- Idempotent: (business_id,recurring_rule_id,recurring_occurrence_date)
-- already has a unique index, and server selects rules FOR UPDATE SKIP LOCKED.
-- Shop timezone America/Chicago is respected across DST transitions.

CREATE OR REPLACE FUNCTION public.briskers_process_due_recurring_transactions(p_through_date date DEFAULT CURRENT_DATE)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  r record;
  occ date;
  next_occ date;
  generated integer := 0;
  curr text;
  category_direction text;
  tx_kind text;
  signed_amount numeric;
  tx uuid;
begin
  for r in
    select rt.*
    from briskers.recurring_transactions rt
    where rt.is_repeating
      and rt.next_date<=coalesce(p_through_date,current_date)
    order by rt.next_date
    for update skip locked
  loop
    if not exists(select 1 from briskers.financial_accounts a
      where a.business_id=r.business_id and a.id=r.account_id and a.active) then
      update briskers.recurring_transactions
      set paused_reason='Account is inactive'
      where id=r.id;
      continue;
    end if;

    if not exists(select 1 from briskers.financial_categories c
      where c.business_id=r.business_id and c.id=r.category_id and c.active) then
      update briskers.recurring_transactions
      set paused_reason='Category is inactive'
      where id=r.id;
      continue;
    end if;

    if r.vendor_id is not null and not exists(select 1 from briskers.vendors v
      where v.business_id=r.business_id and v.id=r.vendor_id and v.active) then
      update briskers.recurring_transactions
      set paused_reason='Payee/payer is inactive'
      where id=r.id;
      continue;
    end if;

    select a.currency_code into curr
    from briskers.financial_accounts a
    where a.business_id=r.business_id and a.id=r.account_id;

    select c.normal_direction into category_direction
    from briskers.financial_categories c
    where c.business_id=r.business_id and c.id=r.category_id;

    tx_kind := case
      when r.direction='expense' and category_direction='income' then 'other_expense'
      when r.direction='expense' then 'supplier_expense'
      when r.direction='income' and category_direction='expense' then 'supplier_refund'
      else 'other_income'
    end;
    signed_amount := case when r.direction='expense' then -r.amount else r.amount end;

    occ := r.next_date;
    while occ<=coalesce(p_through_date,current_date)
      and (r.end_date is null or occ<=r.end_date)
    loop
      if not exists(
        select 1 from briskers.financial_transactions t
        where t.business_id=r.business_id
          and t.recurring_rule_id=r.id
          and t.recurring_occurrence_date=occ
      ) then
        insert into briskers.financial_transactions(
          business_id,account_id,category_id,kind,amount,currency_code,
          transaction_date,vendor_id,remarks,idempotency_key,
          recurring_rule_id,recurring_occurrence_date,created_by
        )
        values(
          r.business_id,r.account_id,r.category_id,tx_kind,signed_amount,curr,
          occ,r.vendor_id,r.remarks,gen_random_uuid(),r.id,occ,r.created_by
        )
        returning id into tx;

        -- Required allocation for posted expenses/refunds. Deferred balance
        -- constraint validates after both rows are inserted atomically.
        IF tx_kind IN ('supplier_expense','other_expense','supplier_refund') THEN
          INSERT INTO briskers.expense_allocations (
            business_id, transaction_id, category_id, amount, created_by
          ) VALUES (
            r.business_id, tx, r.category_id, -signed_amount, r.created_by
          );
        END IF;
        generated := generated+1;
      end if;
      occ := briskers.recurring_next_date(occ,r.frequency,r.interval_count);
    end loop;

    next_occ := occ;
    update briskers.recurring_transactions
    set next_date=next_occ,
        paused_reason=null,
        is_repeating=case
          when end_date is not null and next_occ>end_date then false
          else is_repeating
        end
    where id=r.id;
  end loop;

  return generated;
end
$function$
;

-- Hourly at minute 05, first due run ~00:05 America/Chicago, and hourly
-- catch-up if a previous scheduled run fails or the database was offline.
-- The server uses UTC; through-date is computed in shop-local time, not UTC.
SELECT cron.schedule(
  'briskers-recurring-transactions',
  '5 * * * *',
  $$SELECT public.briskers_process_due_recurring_transactions(
    (clock_timestamp() AT TIME ZONE 'America/Chicago')::date
  );$$
);
