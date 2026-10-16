-- Independent synthetic functions for public CI. These are NOT application
-- implementations, live snapshots, rollback definitions, or deployable RPCs.
-- Only their signatures and permission-entry shape match the migration target.
CREATE OR REPLACE FUNCTION public.briskers_close_invoice(p_business_id uuid, p_invoice_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
begin
  perform briskers.require_permission(p_business_id,'payments.create');
  perform nextval('owner_guard_test.body_calls');
  insert into owner_guard_test.writes(action, business_id, entity_id, actor_id)
    values ('synthetic-close', p_business_id, p_invoice_id, auth.uid());
end
$function$;

CREATE OR REPLACE FUNCTION public.briskers_finalize_pending_invoice_payment(p_business_id uuid, p_invoice_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
begin
  perform briskers.require_permission(p_business_id,'payments.create');
  perform nextval('owner_guard_test.body_calls');
  insert into owner_guard_test.writes(action, business_id, entity_id, actor_id)
    values ('synthetic-finalize', p_business_id, p_invoice_id, auth.uid());
  return p_invoice_id;
end
$function$;
