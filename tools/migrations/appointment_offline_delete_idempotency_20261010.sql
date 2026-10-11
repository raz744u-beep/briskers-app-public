CREATE TABLE IF NOT EXISTS briskers.appointment_delete_operations (
 business_id uuid NOT NULL,operation_id uuid NOT NULL,
 appointment_id uuid NOT NULL,base_version bigint NOT NULL,
 completed_at timestamptz,created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(business_id,operation_id)
);
ALTER TABLE briskers.appointment_delete_operations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON briskers.appointment_delete_operations FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.briskers_sync_offline_appointment_delete(
 p_business_id uuid,p_appointment_id uuid,p_operation_id uuid,p_base_version bigint
) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE op briskers.appointment_delete_operations; a briskers.appointments;
BEGIN
 IF NOT briskers.is_owner(p_business_id) THEN
  RAISE EXCEPTION 'Owner access required' USING ERRCODE='42501';
 END IF;
 IF p_operation_id IS NULL OR p_base_version IS NULL THEN
  RAISE EXCEPTION 'Missing operation ID or revision' USING ERRCODE='22023';
 END IF;
 INSERT INTO briskers.appointment_delete_operations
 (business_id,operation_id,appointment_id,base_version)
 VALUES(p_business_id,p_operation_id,p_appointment_id,p_base_version)
 ON CONFLICT(business_id,operation_id) DO NOTHING;
 SELECT * INTO STRICT op FROM briskers.appointment_delete_operations
 WHERE business_id=p_business_id AND operation_id=p_operation_id FOR UPDATE;
 IF op.appointment_id IS DISTINCT FROM p_appointment_id OR
    op.base_version IS DISTINCT FROM p_base_version THEN
  RAISE EXCEPTION 'Deletion key reused with changed request' USING ERRCODE='23505';
 END IF;
 IF op.completed_at IS NOT NULL THEN RETURN true; END IF;
 SELECT * INTO a FROM briskers.appointments
 WHERE business_id=p_business_id AND id=p_appointment_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Appointment missing or deleted by another operation' USING ERRCODE='40001'; END IF;
 IF a.row_version<>p_base_version THEN
  RAISE EXCEPTION 'Appointment changed on another device' USING ERRCODE='40001';
 END IF;
 PERFORM public.briskers_delete_appointment(p_business_id,p_appointment_id);
 UPDATE briskers.appointment_delete_operations SET completed_at=clock_timestamp()
 WHERE business_id=p_business_id AND operation_id=p_operation_id;
 RETURN true;
END $fn$;
REVOKE ALL ON FUNCTION public.briskers_sync_offline_appointment_delete(uuid,uuid,uuid,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.briskers_sync_offline_appointment_delete(uuid,uuid,uuid,bigint) TO authenticated;
