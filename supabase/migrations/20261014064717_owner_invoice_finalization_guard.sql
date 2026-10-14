-- PREPARED ONLY. Applying this security change requires separate approval.
-- Source: read-only Briskers Dev pg_get_functiondef snapshot, 2026-10-14.
-- Both RPCs can move payments to the posted ledger; close can auto-finalize.
-- This atomic DO statement changes only their entry-point authorization.
-- Exact full-body SHA-256 allowlists reject any unreviewed drift, including
-- declaration initializers, reordered checks, altered math or duplicate guards.
-- Rerunning on either exact patched body is a no-op. Never DROP either function.
DO $owner_guard_migration$
DECLARE
  v_target record;
  v_oid oid;
  v_source text;
  v_definition text;
  v_patched_source text;
  v_patched_definition text;
  v_hash text;
  v_metadata jsonb;
  v_after_metadata jsonb;
  v_comment text;
  v_guard constant text := $guard$  IF auth.uid() IS NULL OR briskers.is_owner(p_business_id) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Owner access required' USING ERRCODE='42501';
  END IF;
$guard$;
  v_anchor constant text := E'begin\n  perform briskers.require_permission(p_business_id,''payments.create'');';
BEGIN
  IF to_regprocedure('auth.uid()') IS NULL
     OR to_regprocedure('briskers.is_owner(uuid)') IS NULL THEN
    RAISE EXCEPTION 'Owner guard dependencies are missing' USING ERRCODE = '55000';
  END IF;

  FOR v_target IN
    SELECT * FROM (VALUES
      ('public.briskers_close_invoice(uuid,uuid)', '7edf674b193a258fbb6bbd13505c30751c5d34ea00a5fe8617ad95a14aa016a4', 'a8e52d779e148a2dfb65e4f92fdbcdd5013cdf778ed251772ca5a450dcd90a57'),
      ('public.briskers_finalize_pending_invoice_payment(uuid,uuid)', 'ecc103aaa6020873493d74b35bef4e5262feb0d661a5be9e93cbfb615ba917e7', '5a4a4a88ace66a3d7cae2f5955f2ad00c473a313e75cb15276f6de559dd21d03')
    ) AS targets(signature, original_sha256, guarded_sha256)
  LOOP
    v_oid := to_regprocedure(v_target.signature);
    IF v_oid IS NULL THEN
      RAISE EXCEPTION 'Owner guard target is missing: %', v_target.signature
        USING ERRCODE = '55000';
    END IF;

    SELECT p.prosrc, to_jsonb(p) - 'prosrc', obj_description(p.oid, 'pg_proc')
      INTO v_source, v_metadata, v_comment
      FROM pg_catalog.pg_proc p WHERE p.oid = v_oid;
    IF v_metadata ->> 'prolang' IS DISTINCT FROM
         (SELECT oid::text FROM pg_catalog.pg_language WHERE lanname = 'plpgsql')
       OR v_metadata ->> 'prosecdef' IS DISTINCT FROM 'true'
       OR v_metadata -> 'proconfig' IS DISTINCT FROM '["search_path=\"\""]'::jsonb
       OR v_metadata ->> 'prokind' IS DISTINCT FROM 'f'
       OR v_metadata ->> 'proisstrict' IS DISTINCT FROM 'false'
       OR v_metadata -> 'proargnames' IS DISTINCT FROM
         '["p_business_id", "p_invoice_id"]'::jsonb THEN
      RAISE EXCEPTION 'Unexpected owner guard target metadata: %', v_target.signature
        USING ERRCODE = '55000';
    END IF;

    v_hash := encode(sha256(convert_to(v_source, 'UTF8')), 'hex');
    IF v_hash = v_target.guarded_sha256 THEN
      CONTINUE;
    END IF;
    IF v_hash IS DISTINCT FROM v_target.original_sha256 THEN
      RAISE EXCEPTION 'Unreviewed function body for %; refusing owner guard patch', v_target.signature
        USING ERRCODE = '55000';
    END IF;
    IF strpos(v_source, v_anchor) = 0
       OR length(v_source) - length(replace(v_source, v_anchor, '')) <> length(v_anchor)
       OR v_source ~* '\mis_owner\M' THEN
      RAISE EXCEPTION 'Unexpected owner guard entry point: %', v_target.signature
        USING ERRCODE = '55000';
    END IF;

    v_patched_source := replace(v_source, v_anchor,
      E'begin\n' || v_guard || '  perform briskers.require_permission(p_business_id,''payments.create'');');
    IF encode(sha256(convert_to(v_patched_source, 'UTF8')), 'hex')
         IS DISTINCT FROM v_target.guarded_sha256 THEN
      RAISE EXCEPTION 'Owner guard source verification failed: %', v_target.signature
        USING ERRCODE = '55000';
    END IF;
    v_definition := pg_get_functiondef(v_oid);
    IF length(v_definition) - length(replace(v_definition, v_source, '')) <> length(v_source) THEN
      RAISE EXCEPTION 'Ambiguous owner guard function definition: %', v_target.signature
        USING ERRCODE = '55000';
    END IF;
    v_patched_definition := replace(v_definition, v_source, v_patched_source);
    EXECUTE v_patched_definition;

    SELECT to_jsonb(p) - 'prosrc' INTO v_after_metadata
      FROM pg_catalog.pg_proc p WHERE p.oid = v_oid;
    IF v_after_metadata IS DISTINCT FROM v_metadata
       OR (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid = v_oid)
            IS DISTINCT FROM v_patched_source
       OR obj_description(v_oid, 'pg_proc') IS DISTINCT FROM v_comment THEN
      RAISE EXCEPTION 'Owner guard changed unexpected body, metadata, ACL or comment: %', v_target.signature
        USING ERRCODE = '55000';
    END IF;
  END LOOP;
END;
$owner_guard_migration$;
