CREATE FUNCTION owner_guard_test.restore_originals() RETURNS void LANGUAGE plpgsql AS $$
DECLARE f record;
BEGIN
  FOR f IN SELECT * FROM owner_guard_test.original_functions LOOP EXECUTE f.definition; END LOOP;
END;
$$;
CREATE FUNCTION owner_guard_test.assert_migration_rejected(label text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE before_functions jsonb; after_functions jsonb; code text;
BEGIN
  SELECT jsonb_agg(to_jsonb(p) ORDER BY p.oid) INTO before_functions FROM pg_proc p
    WHERE p.oid IN (SELECT oid FROM owner_guard_test.original_functions);
  BEGIN
    PERFORM owner_guard_test.apply_migration();
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code = RETURNED_SQLSTATE;
  END;
  SELECT jsonb_agg(to_jsonb(p) ORDER BY p.oid) INTO after_functions FROM pg_proc p
    WHERE p.oid IN (SELECT oid FROM owner_guard_test.original_functions);
  PERFORM owner_guard_test.assert_true(code = '55000' AND before_functions = after_functions,
    label || ': rejected atomically, no partial patch');
END;
$$;
-- Original permission entry point still matches, but any unreviewed body drift
-- must reject. The first target must roll back if the second target fails.
SELECT owner_guard_test.restore_originals();
DO $$
DECLARE f record;
BEGIN
  SELECT * INTO f FROM owner_guard_test.original_functions
    WHERE oid = 'public.briskers_finalize_pending_invoice_payment(uuid,uuid)'::regprocedure;
  EXECUTE replace(f.definition, f.prosrc, f.prosrc || E'\n-- unreviewed drift\n');
END;
$$;
SELECT owner_guard_test.assert_migration_rejected('second target body drift');

SELECT owner_guard_test.restore_originals();
DO $$
DECLARE f record;
BEGIN
  SELECT * INTO f FROM owner_guard_test.original_functions
    WHERE oid = 'public.briskers_close_invoice(uuid,uuid)'::regprocedure;
  EXECUTE replace(f.definition, 'payments.create', 'invoices.edit');
END;
$$;
SELECT owner_guard_test.assert_migration_rejected('permission entry point drift');

SELECT owner_guard_test.restore_originals();
DO $$
DECLARE f record;
BEGIN
  SELECT * INTO f FROM owner_guard_test.patched_functions
    WHERE oid = 'public.briskers_close_invoice(uuid,uuid)'::regprocedure;
  EXECUTE replace(f.definition, E'begin\n', E'begin\n  UPDATE owner_guard_test.writes SET action = ''unexpected'';\n');
END;
$$;
SELECT owner_guard_test.assert_migration_rejected('unexpected statement before guard');

SELECT owner_guard_test.restore_originals();
DO $$
DECLARE f record;
BEGIN
  SELECT * INTO f FROM owner_guard_test.patched_functions
    WHERE oid = 'public.briskers_close_invoice(uuid,uuid)'::regprocedure;
  EXECUTE replace(f.definition, '  IF auth.uid() IS NULL',
    E'  IF briskers.is_owner(p_business_id) IS DISTINCT FROM true THEN\n'
    || E'    RAISE EXCEPTION ''duplicate guard'' USING ERRCODE = ''42501'';\n  END IF;\n'
    || '  IF auth.uid() IS NULL');
END;
$$;
SELECT owner_guard_test.assert_migration_rejected('preexisting additional owner guard');

SELECT owner_guard_test.restore_originals();
ALTER FUNCTION public.briskers_close_invoice(uuid,uuid) SECURITY INVOKER;
SELECT owner_guard_test.assert_migration_rejected('security metadata drift');
SELECT owner_guard_test.restore_originals();
ALTER FUNCTION public.briskers_close_invoice(uuid,uuid) SET search_path = 'public';
SELECT owner_guard_test.assert_migration_rejected('search path drift');
SELECT owner_guard_test.restore_originals();
ALTER FUNCTION public.briskers_close_invoice(uuid,uuid) STRICT;
SELECT owner_guard_test.assert_migration_rejected('null-call bypass metadata drift');

SELECT owner_guard_test.restore_originals();
DROP FUNCTION public.briskers_finalize_pending_invoice_payment(uuid,uuid);
SELECT owner_guard_test.assert_migration_rejected('missing second target');
SELECT owner_guard_test.restore_originals();
DROP FUNCTION briskers.is_owner(uuid);
SELECT owner_guard_test.assert_migration_rejected('missing owner helper');
SELECT owner_guard_test.assert_true(true, 'all isolated owner guard checks complete');
