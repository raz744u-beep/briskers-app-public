-- SYNTHETIC ONLY. Preview precedes A's write; execute waits behind A's write.
\set ON_ERROR_STOP on
SET statement_timeout='8s';
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
SELECT set_config('test.cleanup_fingerprint',public.briskers_test_job_cleanup_preview_v1('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001')->>'fingerprint',false);
SELECT pg_advisory_lock(960100);
SELECT public.test_cleanup_wait_signal(960101);
DO $$ BEGIN
 BEGIN
  PERFORM public.briskers_test_job_cleanup_execute_v1('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001',current_setting('test.cleanup_fingerprint'),'DELETE TEST J-100');
  RAISE EXCEPTION 'FAIL: cleanup ignored newly committed payment';
 EXCEPTION WHEN serialization_failure THEN NULL;
 END;
 IF NOT EXISTS(SELECT 1 FROM briskers.jobs WHERE id='40000000-0000-0000-0000-000000000001')
 OR EXISTS(SELECT 1 FROM briskers_cleanup_private.audit) THEN
  RAISE EXCEPTION 'FAIL: race left a deletion or audit';
 END IF;
END $$;
DELETE FROM briskers.invoice_pending_payments WHERE invoice_id='50000000-0000-0000-0000-000000000001';
SELECT pg_advisory_unlock_all();
SELECT 'PASS: payment committed while execute waited; fresh locked snapshot rejected cleanup' AS result;
