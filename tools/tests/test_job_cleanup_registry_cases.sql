-- SYNTHETIC ONLY. Run after functional cases. Test registry behavior directly,
-- including same-identity updates and actual authenticated/anon role boundaries.
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
SET statement_timeout='8s';
INSERT INTO briskers.jobs(id,business_id,customer_id,job_number,title)
VALUES('40000000-0000-0000-0000-000000000080','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','J-800','Ordinary synthetic create');
INSERT INTO briskers.sales_documents(id,business_id,customer_id,kind)
VALUES('50000000-0000-0000-0000-000000000080','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','estimate');
SELECT public.test_cleanup_assert((SELECT count(*) FROM briskers_cleanup_private.identity_registry WHERE entity_id IN ('40000000-0000-0000-0000-000000000080','50000000-0000-0000-0000-000000000080') AND NOT deleted)=2,'ordinary creates register live job and document identities');
UPDATE briskers.jobs SET id=id,title='Identity-key update' WHERE id='40000000-0000-0000-0000-000000000080';
UPDATE briskers.sales_documents SET id=id,memo='Identity-key update' WHERE id='50000000-0000-0000-0000-000000000080';
SELECT public.test_cleanup_assert((SELECT count(*) FROM briskers_cleanup_private.identity_registry WHERE entity_id IN ('40000000-0000-0000-0000-000000000080','50000000-0000-0000-0000-000000000080') AND NOT deleted)=2,'same-identity upsert guards remain valid');
UPDATE briskers.jobs SET id='40000000-0000-0000-0000-000000000081' WHERE id='40000000-0000-0000-0000-000000000080';
UPDATE briskers.sales_documents SET id='50000000-0000-0000-0000-000000000081' WHERE id='50000000-0000-0000-0000-000000000080';
SELECT public.test_cleanup_assert((SELECT count(*) FROM briskers_cleanup_private.identity_registry WHERE entity_id IN ('40000000-0000-0000-0000-000000000081','50000000-0000-0000-0000-000000000081') AND NOT deleted)=2,'new identity keys register without affecting ordinary writes');
DO $$ BEGIN
 BEGIN UPDATE briskers.jobs SET business_id='10000000-0000-0000-0000-000000000002' WHERE id='40000000-0000-0000-0000-000000000081';
 RAISE EXCEPTION 'FAIL: registered Job moved across businesses'; EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
 BEGIN UPDATE briskers.sales_documents SET id='50000000-0000-0000-0000-000000000002' WHERE id='50000000-0000-0000-0000-000000000081';
 RAISE EXCEPTION 'FAIL: identity update reused tombstoned document'; EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
END $$;
SELECT public.test_cleanup_assert((SELECT business_id FROM briskers.jobs WHERE id='40000000-0000-0000-0000-000000000081')='10000000-0000-0000-0000-000000000001','cross-business identity mutation rolled back');
SELECT public.test_cleanup_assert((SELECT count(*) FROM briskers.sales_documents WHERE id='50000000-0000-0000-0000-000000000081')=1,'blocked identity update preserved document');
SET ROLE authenticated;
SELECT public.briskers_test_job_cleanup_preview_v1('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000008');
DO $$ BEGIN
 BEGIN UPDATE briskers_cleanup_private.rollout SET enabled=true;
 RAISE EXCEPTION 'FAIL: authenticated caller changed private gate'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN DELETE FROM briskers_cleanup_private.tombstones;
 RAISE EXCEPTION 'FAIL: authenticated caller removed tombstones'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
DO $$ BEGIN
 BEGIN PERFORM public.briskers_test_job_cleanup_preview_v1('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000008');
 RAISE EXCEPTION 'FAIL: authenticated mechanic used owner preview'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
SELECT public.briskers_test_job_cleanup_tombstones_v1('10000000-0000-0000-0000-000000000001');
RESET ROLE;
SET ROLE anon;
DO $$ BEGIN
 BEGIN PERFORM public.briskers_test_job_cleanup_tombstones_v1('10000000-0000-0000-0000-000000000001');
 RAISE EXCEPTION 'FAIL: anonymous caller read tombstones'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
DELETE FROM briskers.sales_documents WHERE id='50000000-0000-0000-0000-000000000081';
DELETE FROM briskers.jobs WHERE id='40000000-0000-0000-0000-000000000081';
SELECT public.test_cleanup_assert((SELECT count(*) FROM briskers_cleanup_private.audit)=1,'ordinary writes and denied permissions did not create cleanup audits');
