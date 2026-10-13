-- SYNTHETIC ONLY. Run concurrently with payment_race_b in a disposable cluster.
\set ON_ERROR_STOP on
SET statement_timeout='8s';
SELECT public.test_cleanup_wait_signal(960100);
BEGIN;
INSERT INTO briskers.invoice_pending_payments(invoice_id,business_id,amount,payment_method_id,account_id)
VALUES('50000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',1,'70000000-0000-0000-0000-000000000002','70000000-0000-0000-0000-000000000001');
SELECT pg_advisory_lock(960101);
SELECT pg_sleep(1);
COMMIT;
SELECT pg_advisory_unlock_all();
