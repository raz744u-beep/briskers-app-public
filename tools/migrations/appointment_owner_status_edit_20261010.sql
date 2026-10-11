-- APP-001 owner and secretary appointment edit permissions.
-- Preserve relationships: for checked-in/linked appointments, the owner may
-- correct only scheduling/text/assigned employee without changing customer or
-- vehicle identity underneath an existing Job.
CREATE OR REPLACE FUNCTION public.briskers_update_appointment(
 p_business_id uuid, p_appointment_id uuid, p_customer_id uuid,
 p_vehicle_id uuid, p_title text, p_description text,
 p_starts_at timestamptz, p_ends_at timestamptz,
 p_employee_id uuid DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE a briskers.appointments;
BEGIN
 PERFORM briskers.require_permission(p_business_id,'schedule.manage');
 SELECT * INTO a FROM briskers.appointments
 WHERE business_id=p_business_id AND id=p_appointment_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Appointment not found' USING ERRCODE='P0002'; END IF;
 IF a.status <> 'confirmed' AND NOT briskers.is_owner(p_business_id) THEN
   RAISE EXCEPTION 'Owner approval required to edit this status' USING ERRCODE='42501';
 END IF;
 IF a.job_id IS NOT NULL THEN
   IF NOT briskers.is_owner(p_business_id) THEN
      RAISE EXCEPTION 'Checked-in appointment editing requires owner' USING ERRCODE='42501';
   END IF;
   IF p_customer_id IS DISTINCT FROM a.customer_id
      OR p_vehicle_id IS DISTINCT FROM a.vehicle_id THEN
      RAISE EXCEPTION 'Cannot reassign a checked-in appointment to another customer or vehicle'
        USING ERRCODE='23514';
   END IF;
 END IF;
 IF p_starts_at IS NULL OR p_ends_at IS NULL OR p_ends_at <= p_starts_at THEN
   RAISE EXCEPTION 'Appointment end must be after start' USING ERRCODE='22023';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM briskers.customers WHERE business_id=p_business_id AND id=p_customer_id AND active) THEN
   RAISE EXCEPTION 'Customer not found' USING ERRCODE='P0002';
 END IF;
 IF p_vehicle_id IS NOT NULL AND NOT EXISTS (
   SELECT 1 FROM briskers.vehicle_customers
   WHERE business_id=p_business_id AND vehicle_id=p_vehicle_id
     AND customer_id=p_customer_id AND (valid_until IS NULL OR valid_until>=current_date)
 ) THEN
   RAISE EXCEPTION 'Vehicle is not associated with this customer' USING ERRCODE='23514';
 END IF;
 UPDATE briskers.appointments SET customer_id=p_customer_id,vehicle_id=p_vehicle_id,
 employee_id=p_employee_id,title=coalesce(nullif(btrim(coalesce(p_title,'')),''),'Appointment'),
 description=nullif(btrim(coalesce(p_description,'')),''),
 starts_at=p_starts_at, ends_at=p_ends_at,updated_at=clock_timestamp(),
 row_version=row_version+1
 WHERE business_id=p_business_id AND id=p_appointment_id;
END
$function$;

-- Owner can delete an unlinked appointment regardless of status.
-- Keep linked Job/request history; a separate audited unlink/void workflow
-- would be necessary before allowing deletion of those records.
CREATE OR REPLACE FUNCTION public.briskers_delete_appointment(
 p_business_id uuid,p_appointment_id uuid
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE a briskers.appointments;
BEGIN
 IF NOT briskers.is_owner(p_business_id) THEN
   RAISE EXCEPTION 'Owner access required' USING ERRCODE='42501';
 END IF;
 SELECT * INTO a FROM briskers.appointments WHERE business_id=p_business_id
 AND id=p_appointment_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Appointment not found' USING ERRCODE='P0002'; END IF;
 IF a.job_id IS NOT NULL OR a.request_id IS NOT NULL THEN
    RAISE EXCEPTION 'Linked appointment history cannot be deleted; unlink through audited workflow'
      USING ERRCODE='23514';
 END IF;
 DELETE FROM briskers.appointments WHERE business_id=p_business_id AND id=p_appointment_id;
END
$function$;
