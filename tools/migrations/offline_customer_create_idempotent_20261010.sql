CREATE TABLE IF NOT EXISTS briskers.customer_create_replay(
 business_id uuid NOT NULL, operation_id text NOT NULL,
 request_payload jsonb NOT NULL, customer_id uuid,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(business_id,operation_id)
);
ALTER TABLE briskers.customer_create_replay ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON briskers.customer_create_replay FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.briskers_offline_create_customer_idempotent(
 p_business_id uuid,p_operation_id text,p_name text,p_email text,
 p_phone text,p_billing_address jsonb
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE operation briskers.customer_create_replay; payload jsonb; customer uuid;
BEGIN
 PERFORM briskers.require_permission(p_business_id,'customers.create');
 IF nullif(trim(p_operation_id),'') IS NULL OR length(p_operation_id)>160
 OR nullif(trim(p_name),'') IS NULL THEN
  RAISE EXCEPTION 'Valid operation ID and customer name required' USING ERRCODE='22023';
 END IF;
 payload:=jsonb_build_object('name',trim(p_name),'email',p_email,
 'phone',p_phone,'billing',coalesce(p_billing_address,'{}'::jsonb));
 INSERT INTO briskers.customer_create_replay(business_id,operation_id,request_payload)
 VALUES(p_business_id,p_operation_id,payload)
 ON CONFLICT(business_id,operation_id) DO NOTHING;
 SELECT * INTO STRICT operation FROM briskers.customer_create_replay
 WHERE business_id=p_business_id AND operation_id=p_operation_id FOR UPDATE;
 IF operation.request_payload IS DISTINCT FROM payload THEN
  RAISE EXCEPTION 'Customer create operation changed after upload' USING ERRCODE='23505';
 END IF;
 IF operation.customer_id IS NOT NULL THEN RETURN operation.customer_id; END IF;
 customer:=public.briskers_create_customer_v2(
  p_business_id,p_name,p_email,p_phone,p_billing_address);
 UPDATE briskers.customer_create_replay SET customer_id=customer
 WHERE business_id=p_business_id AND operation_id=p_operation_id;
 RETURN customer;
END $fn$;
REVOKE ALL ON FUNCTION public.briskers_offline_create_customer_idempotent(uuid,text,text,text,text,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.briskers_offline_create_customer_idempotent(uuid,text,text,text,text,jsonb) TO authenticated;
