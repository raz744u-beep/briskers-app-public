-- Owner-only receipt of already verified payroll records. No transfer or
-- change to the shop's expense ledger is performed by this endpoint.
create table if not exists briskers.payroll_reconciliation_payments (
  business_id uuid not null,
  operation_id text not null,
  employee_id uuid not null,
  payload jsonb not null,
  recorded_at timestamptz not null default now(),
  primary key (business_id, operation_id)
);
create table if not exists briskers.payroll_reconciliation_credits (
  business_id uuid not null,
  employee_id uuid not null,
  job_id text not null,
  invoice_id text not null,
  line_id text not null,
  operation_id text not null,
  primary key (business_id, employee_id, job_id, invoice_id, line_id),
  foreign key (business_id, operation_id)
    references briskers.payroll_reconciliation_payments (business_id, operation_id)
);
alter table briskers.payroll_reconciliation_payments enable row level security;
alter table briskers.payroll_reconciliation_credits enable row level security;
revoke all on briskers.payroll_reconciliation_payments,
  briskers.payroll_reconciliation_credits from public, anon, authenticated;

create or replace function public.briskers_reconcile_payroll_payment(
  p_business_id uuid, p_operation_id text, p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  prior jsonb;
  employee uuid;
  credit jsonb;
  allocation jsonb;
  task jsonb;
  gross bigint := 0;
begin
  if auth.uid() is null or briskers.is_owner(p_business_id) is distinct from true then
    raise exception 'Owner payroll access required' using errcode = '42501';
  end if;
  if p_operation_id is null or length(p_operation_id) not between 1 and 128
     or jsonb_typeof(p_payload) is distinct from 'object'
     or pg_column_size(p_payload) > 262144
     or jsonb_typeof(p_payload->'work') is distinct from 'array'
     or jsonb_array_length(p_payload->'work') not between 1 and 1000 then
    raise exception 'Invalid payroll reconciliation request' using errcode = '22023';
  end if;
  employee := (p_payload->>'employee')::uuid;
  if not exists (select 1 from briskers.employees e
      where e.business_id = p_business_id and e.id = employee) then
    raise exception 'Employee not in this shop' using errcode = '42501';
  end if;

  -- Serializes all deliveries for the shop, including lost-response retries.
  perform pg_advisory_xact_lock(hashtextextended('payroll:' || p_business_id::text, 0));
  select p.payload into prior from briskers.payroll_reconciliation_payments p
    where p.business_id = p_business_id and p.operation_id = p_operation_id;
  if found then
    if prior is distinct from p_payload then
      raise exception 'Conflicting payroll replay' using errcode = '23505';
    end if;
    return jsonb_build_object('operation_id', p_operation_id, 'status', 'recorded');
  end if;

  -- Current regular app verifies hourly labor only. Do not acknowledge an
  -- unsupported payment format or silently drop an advance/adjustment.
  if (p_payload->>'base')::bigint is distinct from 0
     or (p_payload->>'adjustment')::bigint is distinct from 0
     or (p_payload->>'repayment')::bigint is distinct from 0 then
    raise exception 'Unsupported payroll payment format' using errcode = '22023';
  end if;
  insert into briskers.payroll_reconciliation_payments
    (business_id, operation_id, employee_id, payload)
  values (p_business_id, p_operation_id, employee, p_payload);

  for credit in select value from jsonb_array_elements(p_payload->'work') loop
    allocation := (credit->>'id')::jsonb;
    task := (allocation->>0)::jsonb;
    if jsonb_typeof(allocation) is distinct from 'array'
       or jsonb_array_length(allocation) <> 2
       or (allocation->>1) is distinct from employee::text
       or jsonb_typeof(task) is distinct from 'array'
       or jsonb_array_length(task) <> 3
       or nullif(task->>0, '') is null or nullif(task->>1, '') is null
       or nullif(task->>2, '') is null
       or (credit->>'minutes')::bigint is null or (credit->>'minutes')::bigint < 0
       or (credit->>'rate')::bigint is null or (credit->>'rate')::bigint <= 0 then
      raise exception 'Invalid payroll work credit' using errcode = '22023';
    end if;
    gross := gross + ((credit->>'minutes')::bigint * (credit->>'rate')::bigint + 30) / 60;
    insert into briskers.payroll_reconciliation_credits
      (business_id, employee_id, job_id, invoice_id, line_id, operation_id)
    values (p_business_id, employee, task->>0, task->>1, task->>2, p_operation_id);
  end loop;
  if gross is distinct from (p_payload->>'confirmed_net')::bigint then
    raise exception 'Payroll total does not match work credits' using errcode = '22023';
  end if;
  return jsonb_build_object('operation_id', p_operation_id, 'status', 'recorded');
end;
$$;
revoke all on function public.briskers_reconcile_payroll_payment(uuid, text, jsonb) from public, anon;
grant execute on function public.briskers_reconcile_payroll_payment(uuid, text, jsonb) to authenticated;

-- Bind the signed-in mechanic to their own active employee/Job assignment.
-- Return no staff, compensation, or payment details.
create or replace function public.briskers_my_payroll_assignment(
  p_business_id uuid, p_job_id uuid
)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select case when count(*) = 1 then (array_agg(e.id))[1] end
  from briskers.employees e
  join briskers.memberships m
    on m.business_id = e.business_id and m.user_id = e.user_id
  where e.business_id = p_business_id and e.user_id = auth.uid()
    and e.active and m.active and m.role_code = 'mechanic'
    and exists (
      select 1 from briskers.job_assignments a
      where a.business_id = e.business_id and a.employee_id = e.id
        and a.job_id = p_job_id and a.active
    );
$$;
revoke all on function public.briskers_my_payroll_assignment(uuid, uuid) from public, anon;
grant execute on function public.briskers_my_payroll_assignment(uuid, uuid) to authenticated;
