-- Run inside BEGIN READ ONLY with briskers.recovery_test_request set locally.
-- The request supplies a known Owner and existing synthetic or authorized
-- recovery identities. Never commit those private values to this repository.
DO $test$
DECLARE
  request jsonb := current_setting('briskers.recovery_test_request')::jsonb;
  proof jsonb;
  again jsonb;
  denied boolean := false;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',request->>'owner_id',true);
  SET LOCAL ROLE authenticated;
  proof := public.briskers_owner_recovery_lookup_v1(
    (request->>'business_id')::uuid,request->>'invoice_operation_id',
    request->>'customer_operation_id',request->>'local_vehicle_id',
    (request->>'payment_operation_id')::uuid);
  again := public.briskers_owner_recovery_lookup_v1(
    (request->>'business_id')::uuid,request->>'invoice_operation_id',
    request->>'customer_operation_id',request->>'local_vehicle_id',
    (request->>'payment_operation_id')::uuid);
  IF proof IS DISTINCT FROM again OR proof->>'id' IS DISTINCT FROM request->>'invoice_id'
     OR proof->>'business_id' IS DISTINCT FROM request->>'business_id'
     OR (proof->>'total_amount')::numeric IS DISTINCT FROM (request->>'total')::numeric
     OR (proof->>'line_count')::int IS DISTINCT FROM (request->>'line_count')::int
     OR jsonb_array_length(proof->'payments') <> 1
     OR proof->'payments'->0->>'operation_id' IS DISTINCT FROM request->>'payment_operation_id'
     OR (proof->'payments'->0->>'amount')::numeric IS DISTINCT FROM (request->>'payment')::numeric
     OR proof->'initial_visit'->>'job_id' IS DISTINCT FROM proof->>'job_id'
     OR proof->'initial_visit'->>'id' IS NULL THEN
    RAISE EXCEPTION 'Recovery proof assertion failed';
  END IF;
  BEGIN
    PERFORM public.briskers_owner_recovery_lookup_v1(
      (request->>'business_id')::uuid,'synthetic-missing-operation',
      request->>'customer_operation_id',request->>'local_vehicle_id',
      (request->>'payment_operation_id')::uuid);
  EXCEPTION WHEN no_data_found THEN denied:=true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'Missing identity was not rejected'; END IF;
  denied:=false;
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  BEGIN
    PERFORM public.briskers_owner_recovery_lookup_v1(
      (request->>'business_id')::uuid,request->>'invoice_operation_id',
      request->>'customer_operation_id',request->>'local_vehicle_id',
      (request->>'payment_operation_id')::uuid);
  EXCEPTION WHEN insufficient_privilege THEN denied:=true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'Non-owner was not rejected'; END IF;
  IF has_function_privilege('anon','public.briskers_owner_recovery_lookup_v1(uuid,text,text,text,uuid)','EXECUTE')
     OR has_function_privilege('anon','briskers.owner_recovery_lookup_v1(uuid,text,text,text,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'Anonymous access regression';
  END IF;
END $test$;
