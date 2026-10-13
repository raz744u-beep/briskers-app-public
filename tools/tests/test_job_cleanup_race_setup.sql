-- SYNTHETIC ONLY, after schema + migration in a NEW disposable local cluster.
-- Do not run the functional cases first: these races need the original fixtures.
SET statement_timeout='8s';
INSERT INTO briskers_cleanup_private.rollout(business_id,enabled,devices_verified_at,reviewed_by)
VALUES('10000000-0000-0000-0000-000000000001',true,clock_timestamp(),'00000000-0000-0000-0000-000000000001');
INSERT INTO briskers.financial_accounts(id,business_id,name,account_kind)
VALUES('70000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Synthetic account','cash');
INSERT INTO briskers.payment_methods(id,business_id,name)
VALUES('70000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','Synthetic method');
-- Session advisory locks are rendezvous signals, not timing assumptions.
CREATE FUNCTION public.test_cleanup_wait_signal(n integer) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 FOR i IN 1..100 LOOP
  IF EXISTS(SELECT 1 FROM pg_locks WHERE locktype='advisory' AND objid=n::oid AND granted) THEN RETURN; END IF;
  PERFORM pg_sleep(0.05);
 END LOOP;
 RAISE EXCEPTION 'Synthetic race peer did not signal %',n;
END $$;
