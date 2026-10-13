-- SYNTHETIC ONLY. Run after the payment race or in a fresh prepared cluster.
\set ON_ERROR_STOP on
SET statement_timeout='8s';
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
SELECT public.test_cleanup_wait_signal(960102);
SELECT public.briskers_test_job_cleanup_execute_v1('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001',public.briskers_test_job_cleanup_preview_v1('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001')->>'fingerprint','DELETE TEST J-100');
SELECT pg_advisory_lock(960103);
SELECT pg_sleep(2);
SELECT pg_advisory_unlock_all();
