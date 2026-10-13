-- SYNTHETIC ONLY. A establishes an old snapshot before B permanently cleans up.
\set ON_ERROR_STOP on
SET statement_timeout='8s';
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT count(*) FROM briskers.jobs;
SELECT pg_advisory_lock(960102);
SELECT public.test_cleanup_wait_signal(960103);
DO $$ BEGIN
 BEGIN
  INSERT INTO briskers.jobs(id,business_id,customer_id,job_number,title)
  VALUES('40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','J-100','Stale replay');
  RAISE EXCEPTION 'FAIL: old-snapshot replay resurrected deleted Job';
 EXCEPTION WHEN serialization_failure OR SQLSTATE '55000' THEN NULL;
 END;
END $$;
ROLLBACK;
SELECT pg_advisory_unlock_all();
SELECT 'PASS: stale transaction cannot resurrect deleted identity' AS result;
