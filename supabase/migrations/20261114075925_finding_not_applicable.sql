-- Adds an explicit disposition only; no existing finding or financial row changes.
alter table briskers.customer_notes drop constraint customer_notes_finding_status_check;
alter table briskers.customer_notes add constraint customer_notes_finding_status_check
  check (finding_status is null or finding_status in ('open','in_job','resolved','not_applicable'));

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
  if n.finding_status is distinct from 'open' or n.body is distinct from p_original_body then
    raise exception 'Finding changed; reopen it before changing disposition' using errcode='P0001';
  end if;
  if p_body is null or not (p_body=p_original_body or
    left(p_body,length(p_original_body)+22)=p_original_body||E'\nNot Applicable note: ') then
    raise exception 'Original finding description must be preserved' using errcode='22023';
  end if;
  update briskers.customer_notes x set finding_status='not_applicable',body=p_body,
    repair_job_id=null,include_on_invoice=false,resolved_at=clock_timestamp(),
    updated_at=clock_timestamp(),row_version=x.row_version+1
    where x.business_id=p_business_id and x.id=p_finding_id;
  return true;
end $$;
revoke all on function briskers.mark_finding_not_applicable(uuid,uuid,text,text) from public,anon;
grant execute on function briskers.mark_finding_not_applicable(uuid,uuid,text,text) to authenticated;
create or replace function public.briskers_mark_finding_not_applicable(
 p_business_id uuid,p_finding_id uuid,p_original_body text,p_body text
) returns boolean language sql security definer set search_path='' as $$
 select briskers.mark_finding_not_applicable(p_business_id,p_finding_id,p_original_body,p_body)
$$;
revoke all on function public.briskers_mark_finding_not_applicable(uuid,uuid,text,text) from public,anon;
grant execute on function public.briskers_mark_finding_not_applicable(uuid,uuid,text,text) to authenticated;
