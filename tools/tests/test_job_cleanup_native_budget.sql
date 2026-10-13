-- SYNTHETIC ONLY. Native-only timing measurements; no production performance claim.
\set ON_ERROR_STOP on
SET statement_timeout='8s';
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
-- CI uses en_US.utf8. Verify that the regression actually exercises a native
-- comparator different from the pinned byte-order signature.
DO $$ DECLARE native_order text; canonical_order text; BEGIN
 SELECT string_agg(s,'|' ORDER BY s),string_agg(s,'|' ORDER BY s COLLATE "C")
 INTO native_order,canonical_order FROM (VALUES
  ('FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT'),
  ('FOREIGN KEY (business_id, customer_id) REFERENCES briskers.customers(business_id, id) ON DELETE RESTRICT')
 ) q(s);
 PERFORM public.test_cleanup_assert(native_order IS DISTINCT FROM canonical_order,'native en_US comparator differs; canonical schema guard already accepted baseline');
END $$;
INSERT INTO briskers.notification_outbox(business_id,recipient_user_id,event_key,event_kind,payload)
SELECT '10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001',
 'benchmark-'||n,'synthetic-cleanup-benchmark',jsonb_build_object('filler',repeat('x',1024))
FROM generate_series(1,2000) n;
DO $$ DECLARE started timestamptz:=clock_timestamp(); p jsonb; BEGIN
 p:=public.briskers_test_job_cleanup_preview_v1('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000008');
 PERFORM public.test_cleanup_assert(p->>'can_delete'='true','preview tolerates 2000 unrelated 1KiB synthetic outbox payloads');
 RAISE NOTICE 'Synthetic only: 2000 unrelated 1KiB JSON payloads, preview elapsed % ms; not a production performance estimate',extract(epoch FROM clock_timestamp()-started)*1000;
END $$;
DELETE FROM briskers.notification_outbox WHERE event_kind='synthetic-cleanup-benchmark';
CREATE FUNCTION public.test_cleanup_timeout_delete() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN PERFORM pg_sleep(1); RETURN OLD; END $$;
CREATE TRIGGER synthetic_timeout AFTER DELETE ON briskers.jobs FOR EACH ROW EXECUTE FUNCTION public.test_cleanup_timeout_delete();
SET statement_timeout='500ms';
DO $$ BEGIN
 BEGIN
  PERFORM public.briskers_test_job_cleanup_execute_v1('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000008',public.briskers_test_job_cleanup_preview_v1('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000008')->>'fingerprint','DELETE TEST J-200');
  RAISE EXCEPTION 'FAIL: short outer request budget did not cancel cleanup';
 EXCEPTION WHEN query_canceled THEN NULL;
 END;
END $$;
SET statement_timeout='8s';
DROP TRIGGER synthetic_timeout ON briskers.jobs;
SELECT public.test_cleanup_assert((SELECT count(*) FROM briskers.jobs WHERE id='40000000-0000-0000-0000-000000000008')=1,'request timeout preserves Job');
SELECT public.test_cleanup_assert((SELECT count(*) FROM briskers.sales_documents WHERE id='50000000-0000-0000-0000-000000000003')=1,'request timeout preserves document');
SELECT public.test_cleanup_assert((SELECT count(*) FROM briskers_cleanup_private.audit)=1,'request timeout rolls back new audit');
SELECT public.test_cleanup_assert((SELECT count(*) FROM briskers_cleanup_private.tombstones)=3,'request timeout rolls back new tombstones');
SELECT count(*) AS passed_named_assertions FROM public.test_cleanup_assertion_results;
