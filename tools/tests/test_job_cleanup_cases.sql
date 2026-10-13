-- SYNTHETIC ONLY. Load test_job_cleanup_schema.sql, then the migration first.
-- This file mutates only disposable fixtures; every assertion is a SQL error
-- on failure. Never connect these tests to the production/dev Supabase project.
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
SET statement_timeout='8s';
CREATE TABLE public.test_cleanup_assertion_results(description text NOT NULL);
CREATE FUNCTION public.test_cleanup_assert(ok boolean, description text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL: %',description; END IF;
 INSERT INTO public.test_cleanup_assertion_results VALUES(description); END $$;
CREATE FUNCTION public.test_cleanup_preview() RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.briskers_test_job_cleanup_preview_v1('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001')
$$;
SELECT public.test_cleanup_assert(public.test_cleanup_preview()->>'can_delete'='false','gate defaults closed');
SELECT public.test_cleanup_assert(public.test_cleanup_preview()->>'rollout_enabled'='false','gate exposed to client');
SELECT public.test_cleanup_assert(jsonb_array_length(public.test_cleanup_preview()->'documents')=2,'preview includes estimate and invoice');
DO $$ BEGIN
 BEGIN
  PERFORM public.briskers_test_job_cleanup_execute_v1('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001',public.test_cleanup_preview()->>'fingerprint','DELETE TEST J-100');
  RAISE EXCEPTION 'FAIL: disabled gate executed';
 EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
END $$;
SELECT public.test_cleanup_assert((SELECT count(*) FROM briskers_cleanup_private.audit)=0,'blocked execution has no audit or mutation');
-- Private operator gate is the only enable route; synthetic owner verified.
INSERT INTO briskers_cleanup_private.rollout(business_id,enabled,devices_verified_at,reviewed_by)
VALUES('10000000-0000-0000-0000-000000000001',true,clock_timestamp(),'00000000-0000-0000-0000-000000000001');
SELECT public.test_cleanup_assert((SELECT count(*) FROM briskers_cleanup_private.rollout_audit)=1,'rollout enable is audited');
SELECT public.test_cleanup_assert(public.test_cleanup_preview()->>'can_delete'='true','eligible synthetic job enabled');
SELECT public.test_cleanup_assert(public.test_cleanup_preview()->>'fingerprint'=public.test_cleanup_preview()->>'fingerprint','fingerprint is deterministic');
SELECT public.test_cleanup_assert(public.test_cleanup_preview()->'dependencies'->>'briskers.sales_document_lines'='1','line count visible');
-- Unauthenticated, cross-business and non-owner callers must fail on server.
DO $$ BEGIN
 PERFORM set_config('request.jwt.claim.sub','',true);
 BEGIN PERFORM public.test_cleanup_preview(); RAISE EXCEPTION 'FAIL: anonymous preview';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
 PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
 BEGIN PERFORM public.test_cleanup_preview(); RAISE EXCEPTION 'FAIL: mechanic preview';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
 BEGIN PERFORM public.briskers_test_job_cleanup_execute_v1('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','x','DELETE TEST J-100'); RAISE EXCEPTION 'FAIL: mechanic execute';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
 PERFORM public.briskers_test_job_cleanup_tombstones_v1('10000000-0000-0000-0000-000000000001');
 PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
 BEGIN PERFORM public.briskers_test_job_cleanup_preview_v1('10000000-0000-0000-0000-000000000002','40000000-0000-0000-0000-000000000001'); RAISE EXCEPTION 'FAIL: cross-business preview';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
END $$;
-- Owner role remains checked even for granted RPC execution; no private access.
SELECT public.test_cleanup_assert(NOT has_function_privilege('anon','public.briskers_test_job_cleanup_execute_v1(uuid,uuid,text,text)','EXECUTE'),'anonymous execute revoked');
SELECT public.test_cleanup_assert(NOT has_schema_privilege('authenticated','briskers_cleanup_private','USAGE'),'private schema not exposed');
SELECT public.test_cleanup_assert(NOT has_table_privilege('authenticated','briskers_cleanup_private.rollout','UPDATE'),'clients cannot enable rollout');
DO $$ DECLARE p jsonb; BEGIN
 p:=public.test_cleanup_preview();
 BEGIN PERFORM public.briskers_test_job_cleanup_execute_v1('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001',p->>'fingerprint','DELETE TEST J-200'); RAISE EXCEPTION 'FAIL: wrong confirmation';
 EXCEPTION WHEN SQLSTATE '22023' THEN NULL; END;
 UPDATE briskers.sales_document_lines SET name='Changed since preview' WHERE id='60000000-0000-0000-0000-000000000001';
 BEGIN PERFORM public.briskers_test_job_cleanup_execute_v1('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001',p->>'fingerprint','DELETE TEST J-100'); RAISE EXCEPTION 'FAIL: stale preview';
 EXCEPTION WHEN SQLSTATE '40001' THEN NULL; END;
END $$;
-- Protected-number plus durable identity protection (renaming cannot evade it).
UPDATE briskers.jobs SET job_number='J-777' WHERE id='40000000-0000-0000-0000-000000000007';
SELECT public.test_cleanup_assert(public.briskers_test_job_cleanup_preview_v1('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000007')->>'can_delete'='false','protected Job identity survives renumbering');
DO $$ DECLARE s text; BEGIN
 FOREACH s IN ARRAY ARRAY['J-7','J7','J-007','J-11','J12'] LOOP
  UPDATE briskers.jobs SET job_number=s WHERE id='40000000-0000-0000-0000-000000000001';
  PERFORM public.test_cleanup_assert(public.test_cleanup_preview()->>'can_delete'='false','protected job number '||s);
 END LOOP;
 UPDATE briskers.jobs SET job_number='J-100' WHERE id='40000000-0000-0000-0000-000000000001';
 FOREACH s IN ARRAY ARRAY['6331','6332','6334','9999',''] LOOP
  UPDATE briskers.sales_documents SET document_number=s WHERE id='50000000-0000-0000-0000-000000000001';
  PERFORM public.test_cleanup_assert(public.test_cleanup_preview()->>'can_delete'='false','numbered invoice '||s);
 END LOOP;
 UPDATE briskers.sales_documents SET document_number=NULL WHERE id='50000000-0000-0000-0000-000000000001';
 UPDATE briskers.sales_documents SET document_number='1997' WHERE id='50000000-0000-0000-0000-000000000002';
 PERFORM public.test_cleanup_assert(public.test_cleanup_preview()->>'can_delete'='false','protected estimate number');
 UPDATE briskers.sales_documents SET document_number=NULL WHERE id='50000000-0000-0000-0000-000000000002';
 FOREACH s IN ARRAY ARRAY['paid','partial','issued','void','closed','unknown'] LOOP
  UPDATE briskers.sales_documents SET status=s WHERE id='50000000-0000-0000-0000-000000000001';
  PERFORM public.test_cleanup_assert(public.test_cleanup_preview()->>'can_delete'='false','non-draft status '||s);
 END LOOP;
 UPDATE briskers.sales_documents SET status='draft',source_metadata='{"offline_operation_id":"abc"}' WHERE id='50000000-0000-0000-0000-000000000001';
 PERFORM public.test_cleanup_assert(public.test_cleanup_preview()->>'can_delete'='false','offline operation provenance');
 UPDATE briskers.sales_documents SET source_metadata='{}',origin='mobilebiz' WHERE id='50000000-0000-0000-0000-000000000001';
 PERFORM public.test_cleanup_assert(public.test_cleanup_preview()->>'can_delete'='false','imported document');
 UPDATE briskers.sales_documents SET origin='native',source_estimate_id='50000000-0000-0000-0000-000000000003' WHERE id='50000000-0000-0000-0000-000000000001';
 PERFORM public.test_cleanup_assert(public.test_cleanup_preview()->>'can_delete'='false','outgoing cross-job estimate');
 UPDATE briskers.sales_documents SET source_estimate_id=NULL WHERE id='50000000-0000-0000-0000-000000000001';
 UPDATE briskers.sales_documents SET source_estimate_id='50000000-0000-0000-0000-000000000002' WHERE id='50000000-0000-0000-0000-000000000003';
 PERFORM public.test_cleanup_assert(public.test_cleanup_preview()->>'can_delete'='false','incoming cross-job estimate reference');
 UPDATE briskers.sales_documents SET source_estimate_id=NULL WHERE id='50000000-0000-0000-0000-000000000003';
END $$;
INSERT INTO briskers.sales_document_estimate_links(business_id,estimate_id,invoice_id,operation_id)
VALUES('10000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000002','50000000-0000-0000-0000-000000000001','synthetic-link');
SELECT public.test_cleanup_assert(public.test_cleanup_preview()->>'can_delete'='false','merged estimate links protected even within Job');
DELETE FROM briskers.sales_document_estimate_links;
-- Financial/payment objects are never cleaned up, even zero-value rows.
INSERT INTO briskers.financial_accounts(id,business_id,name,account_kind) VALUES('70000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Test account','cash');
INSERT INTO briskers.payment_methods(id,business_id,name) VALUES('70000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','Test method');
INSERT INTO briskers.invoice_pending_payments(invoice_id,business_id,amount,payment_method_id,account_id)
VALUES('50000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',0,'70000000-0000-0000-0000-000000000002','70000000-0000-0000-0000-000000000001');
SELECT public.test_cleanup_assert(public.test_cleanup_preview()->>'can_delete'='false','zero pending payment blocks');
DELETE FROM briskers.invoice_pending_payments;
INSERT INTO briskers.financial_transactions(id,business_id,account_id,kind,amount,transaction_date,idempotency_key)
VALUES('70000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000001','income',1,current_date,gen_random_uuid());
INSERT INTO briskers.payment_allocations(business_id,transaction_id,document_id,gross_amount,tax_amount)
VALUES('10000000-0000-0000-0000-000000000001','70000000-0000-0000-0000-000000000003','50000000-0000-0000-0000-000000000001',1,0);
SELECT public.test_cleanup_assert(public.test_cleanup_preview()->>'can_delete'='false','posted payment blocks');
DELETE FROM briskers.payment_allocations;
INSERT INTO briskers.sync_applied_operations(business_id,operation_id,entity_type,result)
VALUES('10000000-0000-0000-0000-000000000001','test-operation','job','{"job_id":"40000000-0000-0000-0000-000000000001"}');
SELECT public.test_cleanup_assert(public.test_cleanup_preview()->>'can_delete'='false','idempotency replay ledger blocks');
DELETE FROM briskers.sync_applied_operations;
INSERT INTO briskers.notification_outbox(business_id,recipient_user_id,event_key,event_kind,payload)
VALUES('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','test','test','{"document_id":"50000000-0000-0000-0000-000000000001"}');
SELECT public.test_cleanup_assert(public.test_cleanup_preview()->>'can_delete'='false','JSON notification outbox blocks');
DELETE FROM briskers.notification_outbox;
-- Case-insensitive UUIDs inside remote JSON outboxes must not evade detection.
INSERT INTO briskers.sales_documents(id,business_id,customer_id,job_id,kind)
VALUES('abcdef00-0000-0000-0000-000000000abc','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','estimate');
INSERT INTO briskers.notification_outbox(business_id,recipient_user_id,event_key,event_kind,payload)
VALUES('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','uppercase','test','{"document_id":"ABCDEF00-0000-0000-0000-000000000ABC"}');
SELECT public.test_cleanup_assert(public.test_cleanup_preview()->>'can_delete'='false','uppercase UUID JSON outbox blocks');
UPDATE briskers.notification_outbox SET payload='{"document_id":"ABCDEF00000000000000000000000ABC"}';
SELECT public.test_cleanup_assert(public.test_cleanup_preview()->>'can_delete'='false','hyphenless UUID JSON outbox blocks');
DELETE FROM briskers.notification_outbox;
DELETE FROM briskers.sales_documents WHERE id='abcdef00-0000-0000-0000-000000000abc';
-- Future unknown dependency, including a cascading FK, must block rather than
-- silently cascade. Unknown non-FK JSON references are covered too.
CREATE TABLE briskers.future_dependency(id uuid,document_id uuid REFERENCES briskers.sales_documents(id) ON DELETE CASCADE);
INSERT INTO briskers.future_dependency VALUES(gen_random_uuid(),'50000000-0000-0000-0000-000000000001');
SELECT public.test_cleanup_assert(public.test_cleanup_preview()->>'can_delete'='false','unknown future FK blocks');
DROP TABLE briskers.future_dependency;
CREATE TABLE public.future_cross_schema(payload jsonb,job_id uuid REFERENCES briskers.jobs(id));
INSERT INTO public.future_cross_schema VALUES('{}','40000000-0000-0000-0000-000000000001');
SELECT public.test_cleanup_assert(public.test_cleanup_preview()->>'can_delete'='false','cross-schema FK blocks');
DROP TABLE public.future_cross_schema;
ALTER TABLE briskers.jobs ADD COLUMN future_external_ref uuid;
SELECT public.test_cleanup_assert(public.test_cleanup_preview()->>'can_delete'='false','unknown column fails closed');
ALTER TABLE briskers.jobs DROP COLUMN future_external_ref;
UPDATE briskers.job_visits SET work_summary='Real work' WHERE job_id='40000000-0000-0000-0000-000000000001';
SELECT public.test_cleanup_assert(public.test_cleanup_preview()->>'can_delete'='false','service work blocked');
UPDATE briskers.job_visits SET work_summary=NULL WHERE job_id='40000000-0000-0000-0000-000000000001';
UPDATE briskers.document_disclaimers SET signature_required=true;
SELECT public.test_cleanup_assert(public.test_cleanup_preview()->>'can_delete'='false','signature-required child blocked');
UPDATE briskers.document_disclaimers SET signature_required=false;
-- Inject a late failure after all DELETEs to prove atomic rollback includes
-- children, audit, tombstones and the main job, not just a preview guard.
CREATE FUNCTION public.test_cleanup_fail_delete() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Injected late failure' USING ERRCODE='P0001'; END $$;
CREATE TRIGGER synthetic_delete_failure AFTER DELETE ON briskers.jobs FOR EACH ROW EXECUTE FUNCTION public.test_cleanup_fail_delete();
DO $$ DECLARE p jsonb; BEGIN
 p:=public.test_cleanup_preview();
 PERFORM public.test_cleanup_assert(p->>'can_delete'='true','baseline eligible before atomicity test');
 BEGIN PERFORM public.briskers_test_job_cleanup_execute_v1('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001',p->>'fingerprint','DELETE TEST J-100');
 EXCEPTION WHEN SQLSTATE 'P0001' THEN
  IF SQLERRM<>'Injected late failure' THEN RAISE; END IF;
 END;
 PERFORM public.test_cleanup_assert((SELECT count(*) FROM briskers.jobs WHERE id='40000000-0000-0000-0000-000000000001')=1,'rollback kept job');
 PERFORM public.test_cleanup_assert((SELECT count(*) FROM briskers.sales_documents WHERE job_id='40000000-0000-0000-0000-000000000001')=2,'rollback kept both documents');
 PERFORM public.test_cleanup_assert((SELECT count(*) FROM briskers.sales_document_lines)=1,'rollback kept lines');
 PERFORM public.test_cleanup_assert((SELECT count(*) FROM briskers_cleanup_private.audit)=0,'rollback removed audit');
 PERFORM public.test_cleanup_assert((SELECT count(*) FROM briskers_cleanup_private.tombstones)=0,'rollback removed tombstones');
END $$;
DROP TRIGGER synthetic_delete_failure ON briskers.jobs;
-- An unlimited request timeout is not safe for the broad write-lock window.
SET statement_timeout='0';
DO $$ BEGIN
 BEGIN PERFORM public.briskers_test_job_cleanup_execute_v1('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001',public.test_cleanup_preview()->>'fingerprint','DELETE TEST J-100');
 RAISE EXCEPTION 'FAIL: unbounded timeout accepted'; EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
END $$;
SET statement_timeout='8s';
-- Successful clean removal retains unrelated rows and creates permanent sync IDs.
DO $$ DECLARE p jsonb; result jsonb; BEGIN
 p:=public.test_cleanup_preview();
 result:=public.briskers_test_job_cleanup_execute_v1('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001',p->>'fingerprint','DELETE TEST J-100');
 PERFORM public.test_cleanup_assert(jsonb_array_length(result->'deleted_document_ids')=2,'execute returns both estimate and invoice IDs');
 PERFORM public.test_cleanup_assert(result->>'audit_id' IS NOT NULL,'execute returns audit ID');
END $$;
SELECT public.test_cleanup_assert((SELECT count(*) FROM briskers.jobs)=2,'only target Job removed');
SELECT public.test_cleanup_assert((SELECT count(*) FROM briskers.sales_documents)=1,'owned estimate removed; unrelated estimate preserved');
SELECT public.test_cleanup_assert((SELECT count(*) FROM briskers.sales_document_lines)=0,'owned lines removed');
SELECT public.test_cleanup_assert((SELECT count(*) FROM briskers.document_disclaimers)=0,'owned disclaimers removed');
SELECT public.test_cleanup_assert((SELECT count(*) FROM briskers.job_visits)=0,'owned initial visit removed');
SELECT public.test_cleanup_assert((SELECT count(*) FROM briskers.job_status_events)=0,'owned initial status removed');
SELECT public.test_cleanup_assert((SELECT count(*) FROM briskers.customers)=1,'customer retained');
SELECT public.test_cleanup_assert((SELECT count(*) FROM briskers.vehicles)=1,'vehicle retained');
SELECT public.test_cleanup_assert((SELECT count(*) FROM briskers.financial_transactions)=1,'unrelated financial transaction retained');
SELECT public.test_cleanup_assert((SELECT count(*) FROM briskers_cleanup_private.audit)=1,'one deletion audit');
SELECT public.test_cleanup_assert((SELECT count(*) FROM briskers_cleanup_private.tombstones)=3,'all deleted top-level IDs tombstoned');
SELECT public.test_cleanup_assert((SELECT count(*) FROM briskers.sync_job_changes WHERE job_id='40000000-0000-0000-0000-000000000001')>0,'existing job delta feed notified');
SELECT public.test_cleanup_assert(jsonb_array_length(public.briskers_test_job_cleanup_tombstones_v1('10000000-0000-0000-0000-000000000001')->'deleted_document_ids')=2,'cross-device document deletion feed');
DO $$ BEGIN
 BEGIN INSERT INTO briskers.jobs(id,business_id,customer_id,job_number,title)
 VALUES('40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','J-100','Stale create replay');
 RAISE EXCEPTION 'FAIL: job resurrected'; EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
 BEGIN INSERT INTO briskers.sales_documents(id,business_id,customer_id,kind)
 VALUES('50000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','estimate');
 RAISE EXCEPTION 'FAIL: estimate resurrected'; EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
 BEGIN UPDATE briskers.sales_documents SET job_id='40000000-0000-0000-0000-000000000001' WHERE id='50000000-0000-0000-0000-000000000003';
 RAISE EXCEPTION 'FAIL: stale document relinked'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM public.briskers_test_job_cleanup_execute_v1('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001',repeat('a',32),'DELETE TEST J-100');
 RAISE EXCEPTION 'FAIL: repeated deletion succeeded'; EXCEPTION WHEN SQLSTATE 'P0002' THEN NULL; END;
END $$;
-- Member-only UUID feed is available to mechanics after cleanup.
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
SELECT public.test_cleanup_assert(jsonb_array_length(public.briskers_test_job_cleanup_tombstones_v1('10000000-0000-0000-0000-000000000001')->'deleted_job_ids')=1,'mechanic sees cleanup identity');
SELECT 'All cleanup SQL assertions passed.' AS result;
