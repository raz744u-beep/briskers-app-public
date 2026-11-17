-- Apply the locally assigned public number to the existing identity.
create table if not exists briskers.estimate_number_audit (
  business_id uuid not null, estimate_id uuid not null,
  original_number text, public_number text not null,
  actor_id uuid not null, confirmed boolean not null,
  recorded_at timestamptz not null default now(),
  primary key (business_id, estimate_id, public_number)
);
alter table briskers.estimate_number_audit enable row level security;
revoke all on briskers.estimate_number_audit from public, anon, authenticated;

create function public.briskers_sync_estimate_number_v2(
  p_business_id uuid, p_estimate_id uuid, p_public_number text, p_owner_confirmed boolean
) returns void language plpgsql security definer set search_path='' as $$
declare d briskers.sales_documents;
begin
  if auth.uid() is null then raise exception 'Sign-in required' using errcode='42501'; end if;
  perform briskers.require_permission(p_business_id,'estimates.edit');
  if p_public_number is null or p_public_number !~ '^E-[0-9]{1,9}$'
      or substring(p_public_number from 3)::integer = 0 then
    raise exception 'Invalid estimate number' using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('estimate-number:' || p_business_id::text, 0));
  select * into d from briskers.sales_documents
    where business_id=p_business_id and id=p_estimate_id and kind='estimate' for update;
  if not found then raise exception 'Estimate identity unavailable' using errcode='PT409'; end if;
  if upper(btrim(d.document_number)) in (p_public_number,substring(p_public_number from 3)) then
    return;
  end if;
  if coalesce(btrim(d.document_number),'') ~* '^(E-)?[0-9]{1,9}$' then
    raise exception 'Estimate already has a different assigned number' using errcode='PT409';
  end if;
  if d.status is distinct from 'draft' and
      (p_owner_confirmed is distinct from true or briskers.is_owner(p_business_id) is distinct from true) then
    raise exception 'Owner confirmation is required for an issued estimate' using errcode='PT409';
  end if;
  if exists(select 1 from briskers.sales_documents other
      where other.business_id=p_business_id and other.kind='estimate' and other.id<>p_estimate_id
        and case when coalesce(btrim(other.document_number),'') ~* '^(E-)?[0-9]{1,9}$'
          then regexp_replace(upper(btrim(other.document_number)),'^E-','')::integer
            = substring(p_public_number from 3)::integer else false end) then
    raise exception 'Estimate number is already assigned' using errcode='PT409';
  end if;
  insert into briskers.estimate_number_audit
    (business_id,estimate_id,original_number,public_number,actor_id,confirmed)
    values(p_business_id,p_estimate_id,d.document_number,p_public_number,auth.uid(),coalesce(p_owner_confirmed,false))
    on conflict do nothing;
  update briskers.sales_documents set document_number=p_public_number
    where business_id=p_business_id and id=p_estimate_id;
end $$;

create function public.briskers_sync_offline_standalone_estimate_v2(
  p_business_id uuid, p_customer_id uuid, p_vehicle_id uuid, p_operation_id uuid,
  p_public_number text, p_document_date date, p_lines jsonb, p_memo text
) returns uuid language plpgsql security invoker set search_path='' as $$
declare id uuid;
begin
  id := public.briskers_sync_offline_standalone_estimate_v1(
    p_business_id,p_customer_id,p_vehicle_id,p_operation_id,p_document_date,p_lines,p_memo);
  perform public.briskers_sync_estimate_number_v2(p_business_id,id,p_public_number,false);
  return id;
end $$;

create function public.briskers_sync_offline_job_estimate_v2(
  p_business_id uuid, p_job_id uuid, p_operation_id uuid,
  p_public_number text, p_document_date date, p_lines jsonb, p_memo text
) returns uuid language plpgsql security invoker set search_path='' as $$
declare id uuid;
begin
  id := public.briskers_sync_offline_job_estimate_v1(
    p_business_id,p_job_id,p_operation_id,p_document_date,p_lines,p_memo);
  perform public.briskers_sync_estimate_number_v2(p_business_id,id,p_public_number,false);
  return id;
end $$;

revoke all on function public.briskers_sync_estimate_number_v2(uuid,uuid,text,boolean) from public,anon;
revoke all on function public.briskers_sync_offline_standalone_estimate_v2(uuid,uuid,uuid,uuid,text,date,jsonb,text) from public,anon;
revoke all on function public.briskers_sync_offline_job_estimate_v2(uuid,uuid,uuid,text,date,jsonb,text) from public,anon;
grant execute on function public.briskers_sync_estimate_number_v2(uuid,uuid,text,boolean) to authenticated;
grant execute on function public.briskers_sync_offline_standalone_estimate_v2(uuid,uuid,uuid,uuid,text,date,jsonb,text) to authenticated;
grant execute on function public.briskers_sync_offline_job_estimate_v2(uuid,uuid,uuid,text,date,jsonb,text) to authenticated;

create table if not exists briskers.finding_disposition_history (
  business_id uuid not null, finding_id uuid not null, prior_status text,
  repair_job_id uuid, resolved_job_id uuid, actor_id uuid not null,
  recorded_at timestamptz not null default now()
);
alter table briskers.finding_disposition_history enable row level security;
revoke all on briskers.finding_disposition_history from public, anon, authenticated;

create or replace function briskers.mark_finding_not_applicable(
  p_business_id uuid, p_finding_id uuid, p_original_body text, p_body text
) returns boolean language plpgsql security definer set search_path='' as $$
declare n briskers.customer_notes;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  perform briskers.require_permission(p_business_id,'customers.edit');
  select * into n from briskers.customer_notes
    where business_id=p_business_id and id=p_finding_id and note_type='finding' for update;
  if not found then raise exception 'Finding not found' using errcode='P0002'; end if;
  if n.finding_status='not_applicable' and n.body=p_body then return true; end if;
  if n.body is distinct from p_original_body then
    raise exception 'Finding changed; reopen it before changing disposition' using errcode='P0001';
  end if;
  if p_body is null or not (p_body=p_original_body or
    left(p_body,length(p_original_body)+22)=p_original_body||E'\nNot Applicable note: ') then
    raise exception 'Original finding description must be preserved' using errcode='22023';
  end if;
  insert into briskers.finding_disposition_history
    (business_id,finding_id,prior_status,repair_job_id,resolved_job_id,actor_id)
    values(p_business_id,p_finding_id,n.finding_status,n.repair_job_id,n.resolved_job_id,auth.uid());
  update briskers.customer_notes x set finding_status='not_applicable',body=p_body,
    repair_job_id=null,include_on_invoice=false,resolved_at=clock_timestamp(),
    updated_at=clock_timestamp(),row_version=x.row_version+1
    where x.business_id=p_business_id and x.id=p_finding_id;
  return true;
end $$;
