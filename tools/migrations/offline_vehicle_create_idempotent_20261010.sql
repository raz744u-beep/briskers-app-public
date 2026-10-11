CREATE TABLE IF NOT EXISTS briskers.vehicle_create_replay (
 business_id uuid NOT NULL,operation_id text NOT NULL,local_vehicle_id text NOT NULL,
 request_payload jsonb NOT NULL,vehicle_id uuid,created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(business_id,operation_id)
);
ALTER TABLE briskers.vehicle_create_replay ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON briskers.vehicle_create_replay FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.briskers_offline_create_vehicle_idempotent(
 p_business_id uuid,p_operation_id text,p_local_vehicle_id text,p_customer_id uuid,
 p_make text,p_model text,p_year int,p_vin text,p_license_plate text,
 p_license_state text,p_mileage numeric,p_color text,p_key_password text
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE op briskers.vehicle_create_replay; payload jsonb; result_id uuid;
BEGIN
 PERFORM briskers.require_permission(p_business_id,'vehicles.create');
 IF nullif(p_operation_id,'') IS NULL OR nullif(p_local_vehicle_id,'') IS NULL THEN
  RAISE EXCEPTION 'Missing operation identity' USING ERRCODE='22023';
 END IF;
 -- No vehicle key passwords are copied into the replay audit table.
 payload:=jsonb_build_object('local_id',p_local_vehicle_id,'customer_id',p_customer_id,
 'make',p_make,'model',p_model,'year',p_year,'vin',p_vin,
 'plate',p_license_plate,'state',p_license_state,'mileage',p_mileage,'color',p_color);
 INSERT INTO briskers.vehicle_create_replay(business_id,operation_id,local_vehicle_id,request_payload)
 VALUES(p_business_id,p_operation_id,p_local_vehicle_id,payload)
 ON CONFLICT(business_id,operation_id) DO NOTHING;
 SELECT * INTO STRICT op FROM briskers.vehicle_create_replay
 WHERE business_id=p_business_id AND operation_id=p_operation_id FOR UPDATE;
 IF op.request_payload IS DISTINCT FROM payload THEN
  RAISE EXCEPTION 'Vehicle operation key reused with changed payload' USING ERRCODE='23505';
 END IF;
 IF op.vehicle_id IS NOT NULL THEN RETURN op.vehicle_id; END IF;
 result_id:=public.briskers_create_vehicle_v4(p_business_id,p_customer_id,p_make,p_model,
 p_year,p_vin,p_license_plate,p_license_state,p_mileage,p_color,p_key_password);
 UPDATE briskers.vehicle_create_replay SET vehicle_id=result_id
 WHERE business_id=p_business_id AND operation_id=p_operation_id;
 RETURN result_id;
END $fn$;
REVOKE ALL ON FUNCTION public.briskers_offline_create_vehicle_idempotent(uuid,text,text,uuid,text,text,int,text,text,text,numeric,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.briskers_offline_create_vehicle_idempotent(uuid,text,text,uuid,text,text,int,text,text,text,numeric,text,text) TO authenticated;
