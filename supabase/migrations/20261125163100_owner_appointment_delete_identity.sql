-- Coordinate a delete with the existing idempotent appointment create row.
CREATE TABLE IF NOT EXISTS briskers.appointment_create_cancellations_v1 (
  business_id uuid NOT NULL,
  operation_id uuid NOT NULL,
  PRIMARY KEY (business_id,operation_id)
);
ALTER TABLE briskers.appointment_create_cancellations_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON briskers.appointment_create_cancellations_v1 FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION briskers.lock_appointment_creation_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $body$
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'briskers:appointment-create:' || NEW.business_id::text || ':' || NEW.operation_id::text,0));
  IF EXISTS (
    SELECT 1 FROM briskers.appointment_create_cancellations_v1 c
    WHERE c.business_id=NEW.business_id AND c.operation_id=NEW.operation_id
  ) THEN
    RAISE EXCEPTION 'Appointment creation was canceled by the Owner' USING ERRCODE='PT409';
  END IF;
  RETURN NEW;
END
$body$;
REVOKE ALL ON FUNCTION briskers.lock_appointment_creation_v1() FROM PUBLIC;
DROP TRIGGER IF EXISTS briskers_lock_appointment_creation_v1 ON briskers.appointment_create_operations;
CREATE TRIGGER briskers_lock_appointment_creation_v1
  BEFORE INSERT ON briskers.appointment_create_operations
  FOR EACH ROW EXECUTE FUNCTION briskers.lock_appointment_creation_v1();

CREATE OR REPLACE FUNCTION public.briskers_delete_appointment_identity_v1(
  p_business_id uuid, p_appointment_id uuid, p_create_operation uuid
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $body$
DECLARE
  target uuid := p_appointment_id;
BEGIN
  IF auth.uid() IS NULL OR briskers.is_owner(p_business_id) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Owner access required' USING ERRCODE='42501';
  END IF;
  IF (p_appointment_id IS NULL) = (p_create_operation IS NULL) THEN
    RAISE EXCEPTION 'An appointment or its create identity is required' USING ERRCODE='22023';
  END IF;
  IF p_create_operation IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtextextended(
      'briskers:appointment-create:' || p_business_id::text || ':' || p_create_operation::text,0));
    SELECT c.appointment_id INTO target FROM briskers.appointment_create_operations c
    WHERE c.business_id=p_business_id AND c.operation_id=p_create_operation;
  END IF;
  IF target IS NOT NULL THEN
    PERFORM 1 FROM briskers.appointments a
    WHERE a.business_id=p_business_id AND a.id=target FOR UPDATE;
    IF FOUND THEN
      -- Recheck job/request links on the server with the current row locked.
      PERFORM public.briskers_delete_appointment(p_business_id,target);
    END IF;
  END IF;
  IF p_create_operation IS NOT NULL THEN
    INSERT INTO briskers.appointment_create_cancellations_v1
    VALUES(p_business_id,p_create_operation) ON CONFLICT DO NOTHING;
  END IF;
  RETURN target;
END
$body$;
REVOKE ALL ON FUNCTION public.briskers_delete_appointment_identity_v1(uuid,uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.briskers_delete_appointment_identity_v1(uuid,uuid,uuid) TO authenticated;
