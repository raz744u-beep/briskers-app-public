-- Idempotent, business-scoped reconciliation. Installing this function does not
-- run it or change any vendor, recurrence, payment, or expense.
begin;
create or replace function public.briskers_reconcile_counterparty_v1(
  p_business_id uuid, p_id uuid, p_edit jsonb, p_base jsonb
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  vendor briskers.vendors%rowtype;
  desired jsonb;
  previous jsonb;
  current_values jsonb;
  name_value text := btrim(p_edit->>'name');
  active_value boolean := (p_edit->>'active')::boolean;
  category_value uuid := (p_edit->>'default_category_id')::uuid;
  surcharge_value numeric := (p_edit->>'default_surcharge_percent')::numeric;
begin
  perform briskers.require_permission(p_business_id,'settings.manage');
  if p_id is null or (p_edit->>'id')::uuid is distinct from p_id
     or nullif(name_value,'') is null or active_value is null or surcharge_value is null
     or surcharge_value not between 0 and 100 then
    raise exception 'Invalid payee change' using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_business_id::text || lower(name_value),0));
  select * into vendor from briskers.vendors
    where id=p_id and business_id=p_business_id for update;
  desired := jsonb_build_array(name_value,active_value,category_value,surcharge_value);
  if found then
    current_values := jsonb_build_array(vendor.name,vendor.active,vendor.default_category_id,
                                        coalesce(vendor.default_surcharge_percent,0));
    if current_values = desired then return p_id; end if;
    previous := jsonb_build_array(p_base->>'name',coalesce((p_base->>'active')::boolean,true),
       (p_base->>'default_category_id')::uuid,coalesce((p_base->>'default_surcharge_percent')::numeric,0));
    if p_base is null or (p_base->>'id')::uuid is distinct from p_id or current_values <> previous then
      raise exception 'Payee changed on another device; saved change requires review' using errcode='P0001';
    end if;
  elsif p_base is not null then
    raise exception 'Original payee unavailable' using errcode='P0002';
  end if;
  if exists (select 1 from briskers.vendors where business_id=p_business_id
             and id<>p_id and lower(btrim(name))=lower(name_value)) then
    raise exception 'Name belongs to another payee; no records changed' using errcode='23505';
  end if;
  if vendor.id is null then
    insert into briskers.vendors(id,business_id,name,active,created_by)
      values(p_id,p_business_id,name_value,active_value,auth.uid());
  else
    perform public.briskers_save_counterparty(p_business_id,p_id,name_value,active_value);
  end if;
  perform public.briskers_set_counterparty_default_category(p_business_id,p_id,category_value);
  perform public.briskers_set_counterparty_surcharge(p_business_id,p_id,surcharge_value);
  return p_id;
end;
$$;
revoke all on function public.briskers_reconcile_counterparty_v1(uuid,uuid,jsonb,jsonb) from public,anon;
grant execute on function public.briskers_reconcile_counterparty_v1(uuid,uuid,jsonb,jsonb) to authenticated;
commit;
