-- Run ONLY in the disposable Briskers synthetic sandbox. Always rolls back.
begin;
do $$
declare b uuid; c uuid; u uuid; f uuid:=gen_random_uuid(); v bigint; rejected boolean;
begin
 select m.business_id,m.user_id,x.id into strict b,u,c from briskers.memberships m
 join briskers.customers x on x.business_id=m.business_id
 where m.role_code='owner' and m.display_name='Disposable synthetic Owner' limit 1;
 insert into briskers.customer_notes(id,business_id,customer_id,note_type,body,finding_status)
 values(f,b,c,'finding','Synthetic repair','open');
 perform set_config('request.jwt.claim.sub','',true);
 rejected:=false;
 begin perform public.briskers_mark_finding_not_applicable(b,f,'Synthetic repair','Synthetic repair');
 exception when insufficient_privilege then rejected:=true; end;
 assert rejected,'Unauthenticated call must fail';
 perform set_config('request.jwt.claim.sub',u::text,true);
 perform public.briskers_mark_finding_not_applicable(b,f,'Synthetic repair',E'Synthetic repair\nNot Applicable note: Repaired elsewhere');
 select row_version into v from briskers.customer_notes where id=f;
 assert (select finding_status='not_applicable' and body=E'Synthetic repair\nNot Applicable note: Repaired elsewhere' and repair_job_id is null and not include_on_invoice from briskers.customer_notes where id=f);
 perform public.briskers_mark_finding_not_applicable(b,f,'Synthetic repair',E'Synthetic repair\nNot Applicable note: Repaired elsewhere');
 assert (select row_version=v from briskers.customer_notes where id=f),'Retry must not mutate twice';
 perform public.briskers_reopen_vehicle_finding(b,f);
 assert (select finding_status='open' and body=E'Synthetic repair\nNot Applicable note: Repaired elsewhere' from briskers.customer_notes where id=f);
 rejected:=false;
 begin perform public.briskers_mark_finding_not_applicable(b,f,'Stale body','Stale body');
 exception when raise_exception then rejected:=true; end;
 assert rejected,'Stale edit must fail';
 rejected:=false;
 begin perform public.briskers_mark_finding_not_applicable(gen_random_uuid(),f,'Synthetic repair','Synthetic repair');
 exception when insufficient_privilege then rejected:=true; end;
 assert rejected,'Cross-business call must fail';
 assert not has_function_privilege('anon','public.briskers_mark_finding_not_applicable(uuid,uuid,text,text)','EXECUTE');
 assert has_function_privilege('authenticated','public.briskers_mark_finding_not_applicable(uuid,uuid,text,text)','EXECUTE');
end $$;
select 'PASS: auth, tenant boundary, original body, optional note, retry, reopen, stale edit; all fixtures rolled back' as result;
rollback;
