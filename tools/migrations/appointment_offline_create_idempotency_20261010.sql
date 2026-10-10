-- Idempotent creation for appointments originating in local-first mode.
CREATE TABLE IF NOT EXISTS briskers.appointment_create_operations (
 business_id uuid NOT NULL,operation_id uuid NOT NULL,
 request_payload jsonb NOT NULL,appointment_id uuid,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(business_id,operation_id)
);
ALTER TABLE briskers.appointment_create_operations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON briskers.appointment_create_operations FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.briskers_sync_offline_appointment_create(
 p_business_id uuid,p_operation_id uuid,p_customer_id uuid,p_vehicle_id uuid,
 p_title text,p_description text,p_starts_at timestamptz,p_ends_at timestamptz,
 p_employee_id uuid
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE v briskers.appointment_create_operations; payload jsonb; created uuid;
BEGIN
 PERFORM briskers.require_permission(p_business_id,'schedule.manage');
 IF p_operation_id IS NULL THEN
  RAISE EXCEPTION 'Missing appointment create operation ID' USING ERRCODE='22023';
 END IF;
 payload:=jsonb_build_object('customer_id',p_customer_id,'vehicle_id',p_vehicle_id,
 'title',p_title,'description',p_description,'starts_at',p_starts_at,
 'ends_at',p_ends_at,'employee_id',p_employee_id);
 INSERT INTO briskers.appointment_create_operations(business_id,operation_id,request_payload)
 VALUES(p_business_id,p_operation_id,payload)
 ON CONFLICT(business_id,operation_id) DO NOTHING;
 SELECT * INTO STRICT v FROM briskers.appointment_create_operations
 WHERE business_id=p_business_id AND operation_id=p_operation_id FOR UPDATE;
 IF v.request_payload IS DISTINCT FROM payload THEN
  RAISE EXCEPTION 'Operation ID reused with changed appointment' USING ERRCODE='23505';
 END IF;
 IF v.appointment_id IS NOT NULL THEN RETURN v.appointment_id; END IF;
 created:=public.briskers_create_appointment(p_business_id,p_customer_id,
 p_vehicle_id,p_title,p_description,p_starts_at,p_ends_at,p_employee_id);
 UPDATE briskers.appointment_create_operations SET appointment_id=created
 WHERE business_id=p_business_id AND operation_id=p_operation_id;
 RETURN created;
END $fn$;
REVOKE ALL ON FUNCTION public.briskers_sync_offline_appointment_create(uuid,uuid,uuid,uuid,text,text,timestamptz,timestamptz,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.briskers_sync_offline_appointment_create(uuid,uuid,uuid,uuid,text,text,timestamptz,timestamptz,uuid) TO authenticated;
