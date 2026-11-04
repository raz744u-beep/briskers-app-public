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

-- One independent work portion per assigned mechanic and invoice line.
create table if not exists briskers.payroll_shared_labor (
  business_id uuid not null,
  id uuid not null default gen_random_uuid(),
  employee_id uuid not null,
  job_id uuid not null,
  invoice_id uuid not null,
  line_id uuid not null,
  description text not null,
  rate_cents bigint not null check (rate_cents > 0),
  actual_minutes integer not null default 0,
  revision integer not null default 0,
  state text not null default 'Open' check (state in ('Open', 'In Progress', 'Done')),
  completed_date date,
  primary key (business_id, id),
  unique (business_id, employee_id, job_id, invoice_id, line_id)
);
alter table briskers.payroll_shared_labor enable row level security;
revoke all on briskers.payroll_shared_labor from public, anon, authenticated;

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
    if not exists (
      select 1 from briskers.payroll_shared_labor w
      where w.business_id=p_business_id and w.employee_id=employee
        and w.job_id=(task->>0)::uuid and w.invoice_id=(task->>1)::uuid
        and w.line_id=(task->>2)::uuid and w.state='Done'
        and w.actual_minutes=(credit->>'minutes')::integer
        and w.rate_cents=(credit->>'rate')::bigint
        and w.revision=(credit->>'version')::integer
    ) then
      raise exception 'Payroll work is not verified on the server' using errcode='22023';
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

create or replace function public.briskers_assign_payroll_labor(
  p_business_id uuid, p_job_id uuid, p_invoice_id uuid, p_line_id uuid, p_employee_id uuid
)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  assigned integer;
begin
  if auth.uid() is null or briskers.is_owner(p_business_id) is distinct from true then
    raise exception 'Owner payroll access required' using errcode='42501';
  end if;
  insert into briskers.payroll_shared_labor
    (business_id,employee_id,job_id,invoice_id,line_id,description,rate_cents)
  select p_business_id,e.id,d.job_id,d.id,l.id,
    coalesce(nullif(trim(l.description),''),l.name,'Invoice labor'),
    round(rate.hourly_rate * 100)::bigint
  from briskers.sales_documents d
  join briskers.sales_document_lines l on l.business_id=d.business_id and l.document_id=d.id
  join briskers.employees e on e.business_id=d.business_id and e.id=p_employee_id
  join lateral (
    select c.hourly_rate,c.payment_type
    from briskers.employee_compensation c
    where c.business_id=e.business_id and c.employee_id=e.id and c.effective_from<=current_date
    order by c.effective_from desc,c.id desc limit 1
  ) rate on true
  where d.business_id=p_business_id and d.job_id=p_job_id and d.id=p_invoice_id
    and d.kind='invoice' and d.status<>'void' and l.id=p_line_id
    and (l.line_kind in ('labor','labour') or
      (l.line_kind='item' and lower(trim(l.name)) in ('labor','labour')))
    and e.active and e.compensation_enabled and rate.payment_type='hourly'
    and round(rate.hourly_rate * 100)>0
    and exists (select 1 from briskers.job_assignments a
      where a.business_id=d.business_id and a.job_id=d.job_id and a.employee_id=e.id and a.active)
  on conflict (business_id,employee_id,job_id,invoice_id,line_id) do nothing;
  get diagnostics assigned = row_count;
  if assigned=0 and not exists (
    select 1 from briskers.payroll_shared_labor w
    where w.business_id=p_business_id and w.employee_id=p_employee_id
      and w.job_id=p_job_id and w.invoice_id=p_invoice_id and w.line_id=p_line_id
  ) then
    raise exception 'Active assignment, saved invoice labor, or hourly rate is missing'
      using errcode='22023';
  end if;
end;
$$;

create or replace function public.briskers_list_payroll_labor(
  p_business_id uuid, p_job_id uuid default null
)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  is_owner boolean := briskers.is_owner(p_business_id) is true;
  mechanic uuid;
  result jsonb;
begin
  if not is_owner then
    mechanic := public.briskers_my_payroll_assignment(p_business_id,p_job_id);
    if mechanic is null then
      raise exception 'Active payroll assignment required' using errcode='42501';
    end if;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',w.id,'description',w.description,'state',w.state,
    'actual_minutes',w.actual_minutes,'revision',w.revision,
    'paid',case when c.operation_id is null then 0 else 1 end
  ) || case when is_owner then jsonb_build_object(
    'employee_id',w.employee_id,'employee_name',e.display_name,
    'job_id',w.job_id,'invoice_id',w.invoice_id,'line_id',w.line_id,
    'completed_date',w.completed_date,'rate_cents',w.rate_cents,
    'gross_cents',(w.actual_minutes*w.rate_cents+30)/60
  ) else '{}'::jsonb end order by w.id),'[]'::jsonb) into result
  from briskers.payroll_shared_labor w
  join briskers.employees e on e.business_id=w.business_id and e.id=w.employee_id
  left join briskers.payroll_reconciliation_credits c
    on c.business_id=w.business_id and c.employee_id=w.employee_id
      and c.job_id=w.job_id::text and c.invoice_id=w.invoice_id::text and c.line_id=w.line_id::text
  where w.business_id=p_business_id and (p_job_id is null or w.job_id=p_job_id)
    and (is_owner or w.employee_id=mechanic);
  return result;
end;
$$;

create or replace function public.briskers_update_my_payroll_labor(
  p_business_id uuid, p_job_id uuid, p_id uuid, p_revision integer,
  p_minutes integer, p_state text
)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  mechanic uuid := public.briskers_my_payroll_assignment(p_business_id,p_job_id);
  saved briskers.payroll_shared_labor%rowtype;
begin
  if mechanic is null then
    raise exception 'Active payroll assignment required' using errcode='42501';
  end if;
  select * into saved from briskers.payroll_shared_labor w
    where w.business_id=p_business_id and w.job_id=p_job_id and w.id=p_id
      and w.employee_id=mechanic for update;
  if not found then raise exception 'Labor portion not available' using errcode='42501'; end if;
  if saved.revision=p_revision+1 and saved.state=p_state
     and saved.actual_minutes=p_minutes then return; end if;
  if p_revision is null or p_minutes is null or p_minutes not between 0 and 14400
    or p_state is null or saved.revision<>p_revision
    or not ((saved.state='Open' and p_state='In Progress' and p_minutes=0)
      or (saved.state='In Progress' and p_state='Done' and p_minutes>0)) then
    raise exception 'Labor changed or invalid work time' using errcode='22023';
  end if;
  update briskers.payroll_shared_labor w
    set state=p_state, actual_minutes=p_minutes, revision=w.revision+1,
      completed_date=case when p_state='Done' then (now() at time zone 'America/Chicago')::date end
    where w.business_id=p_business_id and w.id=p_id;
end;
$$;
revoke all on function public.briskers_assign_payroll_labor(uuid,uuid,uuid,uuid,uuid),
  public.briskers_list_payroll_labor(uuid,uuid),
  public.briskers_update_my_payroll_labor(uuid,uuid,uuid,integer,integer,text) from public, anon;
grant execute on function public.briskers_assign_payroll_labor(uuid,uuid,uuid,uuid,uuid),
  public.briskers_list_payroll_labor(uuid,uuid),
  public.briskers_update_my_payroll_labor(uuid,uuid,uuid,integer,integer,text) to authenticated;

-- The operation key is derived from the same set of labor portions on every
-- device. Lost responses and restarts therefore cannot mint another receipt.
create or replace function public.briskers_record_shared_payroll(
  p_business_id uuid, p_employee_id uuid, p_ids uuid[], p_date date,
  p_method text, p_confirmed_net bigint, p_reason text
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  work jsonb;
  matched integer;
  operation text;
  week_start date := date_trunc('week',p_date)::date;
begin
  if auth.uid() is null or briskers.is_owner(p_business_id) is distinct from true then
    raise exception 'Owner payroll access required' using errcode='42501';
  end if;
  if coalesce(cardinality(p_ids),0) not between 1 and 1000 or p_date is null
     or p_date>(now() at time zone 'America/Chicago')::date
     or p_method is null or p_method not in ('Cash','Zelle','Check','Card','Other')
     or p_confirmed_net is null or p_confirmed_net<0 then
    raise exception 'Invalid payment confirmation' using errcode='22023';
  end if;
  select count(*),jsonb_agg(jsonb_build_object(
    'id',jsonb_build_array(
      jsonb_build_array(w.job_id,w.invoice_id,w.line_id)::text,w.employee_id
    )::text,'version',w.revision,'minutes',w.actual_minutes,'rate',w.rate_cents
  ) order by w.id) into matched,work
  from briskers.payroll_shared_labor w
  where w.business_id=p_business_id and w.employee_id=p_employee_id
    and w.id=any(p_ids) and w.state='Done'
    and (w.completed_date>=week_start and w.completed_date<week_start+7
      or nullif(trim(p_reason),'') is not null);
  if matched<>cardinality(p_ids) then
    raise exception 'Labor is missing, incomplete, duplicated or outside the confirmed week'
      using errcode='22023';
  end if;
  select 'shared-' || md5(string_agg(id::text,',' order by id))
    into operation from unnest(p_ids) ids(id);
  return public.briskers_reconcile_payroll_payment(
    p_business_id,operation,jsonb_build_object(
      'employee',p_employee_id,'week',week_start,'date',p_date,'method',p_method,
      'work',work,'base',0,'adjustment',0,'reason',coalesce(p_reason,''),
      'repayment',0,'confirmed_net',p_confirmed_net
    )
  );
end;
$$;

create or replace function public.briskers_payroll_payment_history(
  p_business_id uuid, p_employee_id uuid
)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare result jsonb;
begin
  if auth.uid() is null or briskers.is_owner(p_business_id) is distinct from true then
    raise exception 'Owner payroll access required' using errcode='42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'operation_id',p.operation_id,'net',(p.payload->>'confirmed_net')::bigint,
    'method',p.payload->>'method','verified_date',p.payload->>'date',
    'reconciliation_state','reconciled'
  ) order by p.recorded_at desc),'[]'::jsonb) into result
  from briskers.payroll_reconciliation_payments p
  where p.business_id=p_business_id and p.employee_id=p_employee_id;
  return result;
end;
$$;
revoke all on function public.briskers_record_shared_payroll(uuid,uuid,uuid[],date,text,bigint,text),
  public.briskers_payroll_payment_history(uuid,uuid) from public, anon;
grant execute on function public.briskers_record_shared_payroll(uuid,uuid,uuid[],date,text,bigint,text),
  public.briskers_payroll_payment_history(uuid,uuid) to authenticated;
