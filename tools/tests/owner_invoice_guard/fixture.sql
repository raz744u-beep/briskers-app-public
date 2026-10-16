-- Disposable synthetic database only. No application data or private RPC bodies.
DO $preflight$
BEGIN
  IF to_regnamespace('briskers') IS NOT NULL
     OR to_regnamespace('auth') IS NOT NULL
     OR to_regnamespace('owner_guard_test') IS NOT NULL THEN
    RAISE EXCEPTION 'Refusing to install fixtures into a nonempty application database';
  END IF;
END;
$preflight$;
CREATE SCHEMA auth;
CREATE SCHEMA briskers;
CREATE SCHEMA owner_guard_test;
CREATE ROLE owner_guard_test_caller NOLOGIN;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;
CREATE TABLE owner_guard_test.actors (
  scope uuid NOT NULL, subject uuid NOT NULL, designation text NOT NULL,
  enabled boolean NOT NULL, PRIMARY KEY (scope, subject)
);
-- Synthetic helper models the documented business-scoped role contract.
CREATE FUNCTION briskers.is_owner(b uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT count(*) > 0 FROM owner_guard_test.actors m
  WHERE m.scope = b AND m.subject = auth.uid()
    AND m.enabled AND m.designation = 'owner';
$$;
CREATE TABLE owner_guard_test.writes (
  action text NOT NULL, business_id uuid NOT NULL, entity_id uuid, actor_id uuid NOT NULL
);
-- Sequence probes survive exception subtransaction rollback, so denied calls
-- cannot hide entry into a fixture body behind rolled-back table mutations.
CREATE SEQUENCE owner_guard_test.permission_calls;
CREATE SEQUENCE owner_guard_test.body_calls;
CREATE TABLE owner_guard_test.permission_override (deny_owner boolean NOT NULL);
INSERT INTO owner_guard_test.permission_override VALUES (false);
CREATE FUNCTION briskers.require_permission(b uuid, permission text) RETURNS void
LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  PERFORM nextval('owner_guard_test.permission_calls');
  IF permission <> 'payments.create' OR NOT EXISTS (
    SELECT 1 FROM owner_guard_test.actors m WHERE m.scope = b
      AND m.subject = auth.uid() AND m.enabled
      AND m.designation IN ('owner', 'office', 'manager')
      AND NOT (m.designation = 'owner' AND
        (SELECT deny_owner FROM owner_guard_test.permission_override))
  ) THEN
    RAISE EXCEPTION 'Permission denied' USING ERRCODE = '42501';
  END IF;
END;
$$;
GRANT USAGE ON SCHEMA public, auth TO owner_guard_test_caller;

-- Synthetic identities: 1 owner, 2 office, 3 manager, 4 mechanic,
-- 5 inactive owner, 6 owner in business B but office in A, 7 unknown user.
INSERT INTO owner_guard_test.actors VALUES
 ('aaaaaaaa-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','owner',true),
 ('aaaaaaaa-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','office',true),
 ('aaaaaaaa-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000003','manager',true),
 ('aaaaaaaa-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000004','mechanic',true),
 ('aaaaaaaa-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000005','owner',false),
 ('aaaaaaaa-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000006','office',true),
 ('bbbbbbbb-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000006','owner',true);
CREATE FUNCTION owner_guard_test.assert_true(ok boolean, label text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL: %', label; END IF;
  RAISE NOTICE 'PASS: %', label;
END;
$$;
CREATE FUNCTION owner_guard_test.seed() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  TRUNCATE owner_guard_test.writes;
  PERFORM setval('owner_guard_test.permission_calls', 1, false);
  PERFORM setval('owner_guard_test.body_calls', 1, false);
  UPDATE owner_guard_test.permission_override SET deny_owner = false;
END;
$$;
CREATE FUNCTION owner_guard_test.state() RETURNS jsonb LANGUAGE sql AS $$
  SELECT coalesce(jsonb_agg(to_jsonb(w) ORDER BY action, business_id, entity_id, actor_id), '[]'::jsonb)
  FROM owner_guard_test.writes w;
$$;
CREATE FUNCTION owner_guard_test.probes() RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_array(
    (SELECT jsonb_build_array(s.last_value, s.is_called) FROM owner_guard_test.permission_calls s),
    (SELECT jsonb_build_array(s.last_value, s.is_called) FROM owner_guard_test.body_calls s)
  );
$$;
