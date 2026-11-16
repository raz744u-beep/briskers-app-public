-- This file is assembled after fixture.sql and independent synthetic RPC definitions.
REVOKE ALL ON FUNCTION public.briskers_close_invoice(uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.briskers_finalize_pending_invoice_payment(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.briskers_close_invoice(uuid,uuid),
  public.briskers_finalize_pending_invoice_payment(uuid,uuid) TO owner_guard_test_caller;
COMMENT ON FUNCTION public.briskers_close_invoice(uuid,uuid) IS 'Synthetic comment must survive';
ALTER FUNCTION public.briskers_close_invoice(uuid,uuid) COST 147;

CREATE TABLE owner_guard_test.original_functions AS
SELECT p.oid, pg_get_functiondef(p.oid) AS definition, p.prosrc,
  to_jsonb(p) - 'prosrc' AS metadata, obj_description(p.oid, 'pg_proc') AS comment
FROM pg_proc p WHERE p.oid IN (
  'public.briskers_close_invoice(uuid,uuid)'::regprocedure,
  'public.briskers_finalize_pending_invoice_payment(uuid,uuid)'::regprocedure
);
CREATE FUNCTION owner_guard_test.call_rpc(rpc text, business uuid, invoice uuid)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE result text; previous_role text := current_setting('role');
BEGIN
  PERFORM set_config('role', 'owner_guard_test_caller', true);
  BEGIN
    EXECUTE format('SELECT public.%I($1, $2)::text', rpc)
      INTO result USING business, invoice;
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('role', previous_role, true);
    RAISE;
  END;
  PERFORM set_config('role', previous_role, true);
  RETURN result;
END;
$$;
CREATE FUNCTION owner_guard_test.owner_scenario(rpc text, scenario text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE result text;
  business uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
  entity uuid := 'dddddddd-0000-0000-0000-000000000001';
BEGIN
  PERFORM owner_guard_test.seed();
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
  IF scenario = 'null_entity' THEN entity := NULL; END IF;
  result := owner_guard_test.call_rpc(rpc, business, entity);
  IF scenario = 'repeat' THEN result := owner_guard_test.call_rpc(rpc, business, entity); END IF;
  RETURN jsonb_build_object('result',result,'state',owner_guard_test.state(),
    'probes',owner_guard_test.probes());
END;
$$;
CREATE TABLE owner_guard_test.owner_baseline (rpc text, scenario text, outcome jsonb);
INSERT INTO owner_guard_test.owner_baseline
SELECT rpc, scenario, owner_guard_test.owner_scenario(rpc, scenario)
FROM (VALUES ('briskers_finalize_pending_invoice_payment'),('briskers_close_invoice')) AS r(rpc)
CROSS JOIN (VALUES ('normal'),('null_entity'),('repeat')) AS s(scenario);
-- Explicit owner-path assertions prevent two equally failing paths from passing.
SELECT owner_guard_test.assert_true(
  outcome #>> '{state,0,action}' = 'synthetic-finalize'
  AND outcome #>> '{state,0,actor_id}' = '00000000-0000-0000-0000-000000000001'
  AND outcome ->> 'result' = 'dddddddd-0000-0000-0000-000000000001',
  'synthetic owner finalize writes actor and returns entity identity'
) FROM owner_guard_test.owner_baseline WHERE rpc = 'briskers_finalize_pending_invoice_payment' AND scenario = 'normal';
SELECT owner_guard_test.assert_true(
  outcome #>> '{state,0,action}' = 'synthetic-close'
  AND outcome #>> '{state,0,actor_id}' = '00000000-0000-0000-0000-000000000001'
  AND jsonb_array_length(outcome -> 'state') = 1,
  'synthetic owner close writes one probe with JWT identity'
) FROM owner_guard_test.owner_baseline WHERE rpc = 'briskers_close_invoice' AND scenario = 'normal';

-- Verify the fixture permission initially allows office and manager.
DO $$
DECLARE subject text; rpc text; result text;
BEGIN
  FOREACH subject IN ARRAY ARRAY['00000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000003'] LOOP
    FOREACH rpc IN ARRAY ARRAY['briskers_finalize_pending_invoice_payment','briskers_close_invoice'] LOOP
      PERFORM owner_guard_test.seed();
      PERFORM set_config('request.jwt.claim.sub',subject,true);
      result := owner_guard_test.call_rpc(rpc, 'aaaaaaaa-0000-0000-0000-000000000001',
        'dddddddd-0000-0000-0000-000000000001');
      PERFORM owner_guard_test.assert_true(
        (SELECT count(*) = 1 FROM owner_guard_test.writes),
        'synthetic office/manager broad permission baseline: ' || subject || ' / ' || rpc);
    END LOOP;
  END LOOP;
END;
$$;

SELECT owner_guard_test.apply_migration();
SELECT owner_guard_test.assert_true(
  to_jsonb(p) - 'prosrc' = f.metadata
  AND obj_description(p.oid, 'pg_proc') IS NOT DISTINCT FROM f.comment
  AND replace(p.prosrc, $guard$  IF auth.uid() IS NULL OR briskers.is_owner(p_business_id) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Owner access required' USING ERRCODE='42501';
  END IF;
$guard$, '') = f.prosrc,
  'only the owner guard changes; body, OID, ACL, owner, settings and comment remain: ' || p.proname
) FROM owner_guard_test.original_functions f JOIN pg_proc p USING (oid);
CREATE TABLE owner_guard_test.patched_functions AS
SELECT p.oid, pg_get_functiondef(p.oid) AS definition, p.prosrc,
  to_jsonb(p) AS metadata FROM owner_guard_test.original_functions f JOIN pg_proc p USING (oid);
SELECT owner_guard_test.apply_migration();
SELECT owner_guard_test.assert_true(to_jsonb(p) = f.metadata AND pg_get_functiondef(p.oid) = f.definition,
  'second migration run is an exact no-op: ' || p.proname)
FROM owner_guard_test.patched_functions f JOIN pg_proc p USING (oid);
SELECT owner_guard_test.assert_true(
  owner_guard_test.owner_scenario(rpc, scenario) = outcome,
  'owner behavior unchanged: ' || rpc || ' / ' || scenario
) FROM owner_guard_test.owner_baseline;

CREATE FUNCTION owner_guard_test.assert_denied(label text, subject text, business uuid) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE rpc text; before_state jsonb; before_probes jsonb; code text; message text;
BEGIN
  FOREACH rpc IN ARRAY ARRAY['briskers_finalize_pending_invoice_payment','briskers_close_invoice'] LOOP
    PERFORM owner_guard_test.seed();
    PERFORM set_config('request.jwt.claim.sub',subject,true);
    before_state := owner_guard_test.state(); before_probes := owner_guard_test.probes();
    code := NULL; message := NULL;
    BEGIN
      PERFORM owner_guard_test.call_rpc(rpc, business, 'dddddddd-0000-0000-0000-000000000001');
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS code = RETURNED_SQLSTATE, message = MESSAGE_TEXT;
    END;
    PERFORM owner_guard_test.assert_true(code = '42501' AND message = 'Owner access required',
      label || ' rejected by owner guard: ' || rpc);
    PERFORM owner_guard_test.assert_true(before_state = owner_guard_test.state()
      AND before_probes = owner_guard_test.probes(),
      label || ' has no mutations or synthetic-body entry: ' || rpc);
  END LOOP;
END;
$$;
SELECT owner_guard_test.assert_denied(label, subject, 'aaaaaaaa-0000-0000-0000-000000000001')
FROM (VALUES
 ('office','00000000-0000-0000-0000-000000000002'),
 ('manager','00000000-0000-0000-0000-000000000003'),
 ('mechanic','00000000-0000-0000-0000-000000000004'),
 ('inactive owner','00000000-0000-0000-0000-000000000005'),
 ('owner elsewhere / office here','00000000-0000-0000-0000-000000000006'),
 ('unknown user','00000000-0000-0000-0000-000000000007'),
 ('null / unauthenticated','')
) AS denied(label, subject);
SELECT owner_guard_test.assert_denied('owner in other business',
 '00000000-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001');
SELECT owner_guard_test.assert_denied('owner with null business',
 '00000000-0000-0000-0000-000000000001',NULL);

-- Preserve existing payments.create check even for an active owner.
DO $$
DECLARE rpc text; code text; message text; before_state jsonb;
BEGIN
  FOREACH rpc IN ARRAY ARRAY['briskers_finalize_pending_invoice_payment','briskers_close_invoice'] LOOP
    PERFORM owner_guard_test.seed();
    UPDATE owner_guard_test.permission_override SET deny_owner = true;
    PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
    before_state := owner_guard_test.state(); code := NULL; message := NULL;
    BEGIN
      PERFORM owner_guard_test.call_rpc(rpc, 'aaaaaaaa-0000-0000-0000-000000000001',
        'dddddddd-0000-0000-0000-000000000001');
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS code = RETURNED_SQLSTATE, message = MESSAGE_TEXT;
    END;
    PERFORM owner_guard_test.assert_true(code = '42501' AND message = 'Permission denied'
      AND before_state = owner_guard_test.state(), 'owner still requires payments.create: ' || rpc);
  END LOOP;
END;
$$;

-- Fail-closed SQL three-valued logic, independently from membership fixture.
CREATE OR REPLACE FUNCTION briskers.is_owner(b uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$ SELECT NULL::boolean; $$;
SELECT owner_guard_test.assert_denied('NULL owner helper',
 '00000000-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001');
CREATE OR REPLACE FUNCTION briskers.is_owner(b uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$ SELECT true; $$;
SELECT owner_guard_test.assert_denied('unauthenticated even if helper returns true','',
 'aaaaaaaa-0000-0000-0000-000000000001');
