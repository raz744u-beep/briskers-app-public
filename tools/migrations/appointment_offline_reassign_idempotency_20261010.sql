-- Revision-guarded, idempotent customer/vehicle reassignment for synced appointments.
CREATE TABLE IF NOT EXISTS briskers.appointment_reassign_operations (
 business_id uuid NOT NULL, operation_id uuid NOT NULL,
 appointment_id uuid NOT NULL, request_payload jsonb NOT NULL,
 resulting_version bigint, created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(business_id,operation_id)
);
ALTER TABLE briskers.appointment_reassign_operations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON briskers.appointment_reassign_operations FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.briskers_sync_offline_appointment_reassign(
 p_business_id uuid,p_appointment_id uuid,p_operation_id uuid,
 p_base_version bigint,p_customer_id uuid,p_vehicle_id uuid,
 p_title text,p_description text,p_starts_at timestamptz,p_ends_at timestamptz,
 p_employee_id uuid
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE a briskers.appointments; r briskers.appointment_reassign_operations; payload jsonb; v bigint;
BEGIN
 PERFORM briskers.require_permission(p_business_id,'schedule.manage');
 IF p_operation_id IS NULL OR p_base_version IS NULL THEN
  RAISE EXCEPTION 'Missing operation identity or base version' USING ERRCODE='22023';
 END IF;
 payload:=jsonb_build_object('appointment_id',p_appointment_id,'base_version',p_base_version,
 'customer_id',p_customer_id,'vehicle_id',p_vehicle_id,'title',p_title,
 'description',p_description,'starts_at',p_starts_at,'ends_at',p_ends_at,
 'employee_id',p_employee_id);
 INSERT INTO briskers.appointment_reassign_operations(business_id,operation_id,appointment_id,request_payload)
 VALUES(p_business_id,p_operation_id,p_appointment_id,payload)
 ON CONFLICT(business_id,operation_id) DO NOTHING;
 SELECT * INTO STRICT r FROM briskers.appointment_reassign_operations
 WHERE business_id=p_business_id AND operation_id=p_operation_id FOR UPDATE;
 IF r.request_payload IS DISTINCT FROM payload THEN
  RAISE EXCEPTION 'Operation key reused with changed reassignment' USING ERRCODE='23505';
 END IF;
 IF r.resulting_version IS NOT NULL THEN RETURN r.resulting_version; END IF;
 SELECT * INTO a FROM briskers.appointments
 WHERE business_id=p_business_id AND id=p_appointment_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Appointment not found' USING ERRCODE='P0002'; END IF;
 IF a.row_version<>p_base_version THEN
  RAISE EXCEPTION 'Appointment changed on another device' USING ERRCODE='40001';
 END IF;
 IF a.job_id IS NOT NULL THEN
  RAISE EXCEPTION 'Checked-in appointment cannot be reassigned' USING ERRCODE='23514';
 END IF;
 PERFORM public.briskers_update_appointment(p_business_id,p_appointment_id,
 p_customer_id,p_vehicle_id,p_title,p_description,p_starts_at,p_ends_at,p_employee_id);
 SELECT row_version INTO v FROM briskers.appointments
 WHERE business_id=p_business_id AND id=p_appointment_id;
 UPDATE briskers.appointment_reassign_operations SET resulting_version=v
 WHERE business_id=p_business_id AND operation_id=p_operation_id;
 RETURN v;
END $fn$;
REVOKE ALL ON FUNCTION public.briskers_sync_offline_appointment_reassign(uuid,uuid,uuid,bigint,uuid,uuid,text,text,timestamptz,timestamptz,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.briskers_sync_offline_appointment_reassign(uuid,uuid,uuid,bigint,uuid,uuid,text,text,timestamptz,timestamptz,uuid) TO authenticated;
