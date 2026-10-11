CREATE TABLE IF NOT EXISTS briskers.appointment_cancel_operations (
 business_id uuid NOT NULL, operation_id uuid NOT NULL,
 appointment_id uuid NOT NULL, base_version bigint NOT NULL,
 resulting_version bigint, created_at timestamptz DEFAULT now(),
 PRIMARY KEY(business_id,operation_id)
);
ALTER TABLE briskers.appointment_cancel_operations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON briskers.appointment_cancel_operations FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.briskers_sync_offline_appointment_cancel(
 p_business_id uuid,p_appointment_id uuid,p_operation_id uuid,p_base_version bigint
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE existing briskers.appointment_cancel_operations; a briskers.appointments; v bigint;
BEGIN
 PERFORM briskers.require_permission(p_business_id,'schedule.manage');
 IF p_operation_id IS NULL OR p_base_version IS NULL THEN
  RAISE EXCEPTION 'Missing cancellation operation identity/version' USING ERRCODE='22023';
 END IF;
 INSERT INTO briskers.appointment_cancel_operations(business_id,operation_id,appointment_id,base_version)
 VALUES(p_business_id,p_operation_id,p_appointment_id,p_base_version)
 ON CONFLICT(business_id,operation_id) DO NOTHING;
 SELECT * INTO STRICT existing FROM briskers.appointment_cancel_operations
 WHERE business_id=p_business_id AND operation_id=p_operation_id FOR UPDATE;
 IF existing.appointment_id IS DISTINCT FROM p_appointment_id OR
    existing.base_version IS DISTINCT FROM p_base_version THEN
  RAISE EXCEPTION 'Cancellation key reused for different request' USING ERRCODE='23505';
 END IF;
 IF existing.resulting_version IS NOT NULL THEN RETURN existing.resulting_version; END IF;
 SELECT * INTO a FROM briskers.appointments
 WHERE business_id=p_business_id AND id=p_appointment_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Appointment not found' USING ERRCODE='P0002'; END IF;
 IF a.row_version<>p_base_version THEN
  RAISE EXCEPTION 'Appointment changed on another device' USING ERRCODE='40001';
 END IF;
 IF a.status NOT IN ('confirmed','tentative') OR a.job_id IS NOT NULL THEN
  RAISE EXCEPTION 'Appointment cannot be cancelled' USING ERRCODE='23514';
 END IF;
 PERFORM public.briskers_set_appointment_status(p_business_id,p_appointment_id,'cancelled');
 SELECT row_version INTO v FROM briskers.appointments WHERE business_id=p_business_id AND id=p_appointment_id;
 UPDATE briskers.appointment_cancel_operations SET resulting_version=v
 WHERE business_id=p_business_id AND operation_id=p_operation_id;
 RETURN v;
END $fn$;
REVOKE ALL ON FUNCTION public.briskers_sync_offline_appointment_cancel(uuid,uuid,uuid,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.briskers_sync_offline_appointment_cancel(uuid,uuid,uuid,bigint) TO authenticated;
