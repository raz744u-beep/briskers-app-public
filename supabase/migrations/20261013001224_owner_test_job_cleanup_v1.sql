-- Dedicated test-only cleanup. PREPARED ONLY: do not apply without review.
-- Verified read-only against the current schema on 2026-10-13.
-- No existing rows are deleted by this migration. Rollout starts DISABLED.
-- This RPC does not call the older estimate-preserving delete functions.
-- No document/job number is recycled. Customer and vehicle rows are untouched.
-- Execute briefly locks briskers tables against writes to prevent soft-reference
-- and payment phantoms; timeout/conflict aborts the entire transaction.
BEGIN;
CREATE SCHEMA IF NOT EXISTS briskers_cleanup_private;
REVOKE ALL ON SCHEMA briskers_cleanup_private FROM PUBLIC, anon, authenticated;

CREATE TABLE briskers_cleanup_private.rollout (
 business_id uuid PRIMARY KEY,
 enabled boolean NOT NULL DEFAULT false,
 devices_verified_at timestamptz,
 reviewed_by uuid,
 CHECK (NOT enabled OR (devices_verified_at IS NOT NULL AND reviewed_by IS NOT NULL))
);
CREATE TABLE briskers_cleanup_private.rollout_audit (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 business_id uuid NOT NULL,
 changed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 actor_user_id uuid,
 database_actor text NOT NULL,
 old_state jsonb,
 new_state jsonb
);
CREATE FUNCTION briskers_cleanup_private.audit_rollout_change()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $f$
BEGIN
 IF TG_OP<>'DELETE' AND NEW.enabled AND NOT EXISTS(
   SELECT 1 FROM briskers.memberships m WHERE m.business_id=NEW.business_id
     AND m.user_id=NEW.reviewed_by AND m.active AND m.role_code='owner') THEN
   RAISE EXCEPTION 'Rollout reviewer must be an active business owner' USING ERRCODE='42501';
 END IF;
 INSERT INTO briskers_cleanup_private.rollout_audit(business_id,actor_user_id,database_actor,old_state,new_state)
 VALUES(CASE WHEN TG_OP='DELETE' THEN OLD.business_id ELSE NEW.business_id END,
   auth.uid(),session_user,CASE WHEN TG_OP<>'INSERT' THEN to_jsonb(OLD) END,
   CASE WHEN TG_OP<>'DELETE' THEN to_jsonb(NEW) END);
 IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END $f$;
CREATE TRIGGER test_cleanup_rollout_audit AFTER INSERT OR UPDATE OR DELETE
ON briskers_cleanup_private.rollout FOR EACH ROW EXECUTE FUNCTION briskers_cleanup_private.audit_rollout_change();
CREATE TABLE briskers_cleanup_private.protected_entities (
 business_id uuid NOT NULL,
 entity_type text NOT NULL CHECK(entity_type IN ('jobs','sales_documents')),
 entity_id uuid NOT NULL,
 protected_label text NOT NULL,
 PRIMARY KEY (business_id,entity_type,entity_id)
);
-- Snapshot identities so later renumbering cannot evade permanent protection.
INSERT INTO briskers_cleanup_private.protected_entities
SELECT business_id,'jobs',id,job_number FROM briskers.jobs
WHERE regexp_replace(upper(job_number),'[^0-9]','','g') ~ '^0*(7|11|12)$'
UNION ALL
SELECT business_id,'sales_documents',id,document_number
FROM briskers.sales_documents
WHERE (kind='invoice' AND regexp_replace(document_number,'[^0-9]','','g') ~ '^0*(6331|6332|6334)$')
 OR (kind='estimate' AND regexp_replace(document_number,'[^0-9]','','g') ~ '^0*1997$');

CREATE TABLE briskers_cleanup_private.audit (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 business_id uuid NOT NULL,
 job_id uuid NOT NULL,
 actor_user_id uuid NOT NULL,
 executed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 fingerprint text NOT NULL,
 preview jsonb NOT NULL
);
-- Registry UPSERT is a unique-index serialization point, even when an old
-- transaction snapshot cannot see a just-committed tombstone. Only INSERTs or
-- explicit identity changes touch it; ordinary field updates are unaffected.
CREATE TABLE briskers_cleanup_private.identity_registry (
 entity_type text NOT NULL CHECK(entity_type IN ('jobs','sales_documents')),
 entity_id uuid NOT NULL,
 business_id uuid NOT NULL,
 deleted boolean NOT NULL DEFAULT false,
 PRIMARY KEY(entity_type,entity_id)
);
CREATE TABLE briskers_cleanup_private.tombstones (
 business_id uuid NOT NULL,
 entity_type text NOT NULL CHECK(entity_type IN ('jobs','sales_documents')),
 entity_id uuid NOT NULL,
 job_id uuid NOT NULL,
 audit_id uuid NOT NULL REFERENCES briskers_cleanup_private.audit(id),
 deleted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY (business_id,entity_type,entity_id),
 UNIQUE (entity_type,entity_id)
);
ALTER TABLE briskers_cleanup_private.identity_registry ENABLE ROW LEVEL SECURITY;
ALTER TABLE briskers_cleanup_private.rollout ENABLE ROW LEVEL SECURITY;
ALTER TABLE briskers_cleanup_private.rollout_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE briskers_cleanup_private.protected_entities ENABLE ROW LEVEL SECURITY;
ALTER TABLE briskers_cleanup_private.audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE briskers_cleanup_private.tombstones ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA briskers_cleanup_private FROM PUBLIC,anon,authenticated;

CREATE FUNCTION briskers_cleanup_private.guard_deleted_identity()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $f$
DECLARE v_deleted boolean; v_business uuid;
BEGIN
 INSERT INTO briskers_cleanup_private.identity_registry(entity_type,entity_id,business_id)
 VALUES(TG_TABLE_NAME,NEW.id,NEW.business_id)
 ON CONFLICT(entity_type,entity_id) DO UPDATE SET entity_id=EXCLUDED.entity_id
 RETURNING deleted,business_id INTO v_deleted,v_business;
 IF v_deleted OR v_business IS DISTINCT FROM NEW.business_id THEN
   RAISE EXCEPTION 'This identity was deleted or belongs to another business; review stale replay'
     USING ERRCODE='55000';
 END IF;
 RETURN NEW;
END $f$;
CREATE TRIGGER test_cleanup_deleted_identity BEFORE INSERT OR UPDATE OF id,business_id
ON briskers.jobs FOR EACH ROW EXECUTE FUNCTION briskers_cleanup_private.guard_deleted_identity();
CREATE TRIGGER test_cleanup_deleted_identity BEFORE INSERT OR UPDATE OF id,business_id
ON briskers.sales_documents FOR EACH ROW EXECUTE FUNCTION briskers_cleanup_private.guard_deleted_identity();

CREATE FUNCTION briskers_cleanup_private.preview(p_business_id uuid,p_job_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $f$
DECLARE
 j briskers.jobs;
 d briskers.sales_documents;
 r record;
 v_rows jsonb;
 v_bad bigint;
 v_count bigint;
 v_ids uuid[];
 v_doc_ids uuid[];
 v_safe_ids uuid[];
 v_reasons text[] := ARRAY[]::text[];
 v_documents jsonb := '[]'::jsonb;
 v_dependencies jsonb := '{}'::jsonb;
 v_state jsonb := '{}'::jsonb;
 v_enabled boolean;
 v_expected text[];
 v_actual text[];
 v_schema text;
BEGIN
 IF auth.uid() IS NULL OR briskers.is_owner(p_business_id) IS DISTINCT FROM true THEN
   RAISE EXCEPTION 'Owner access required' USING ERRCODE='42501';
 END IF;
 SELECT * INTO j FROM briskers.jobs WHERE business_id=p_business_id AND id=p_job_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Job not found' USING ERRCODE='P0002'; END IF;
 SELECT coalesce((SELECT enabled FROM briskers_cleanup_private.rollout WHERE business_id=p_business_id),false)
 INTO v_enabled;
 IF NOT v_enabled THEN
   v_reasons:=array_append(v_reasons,'Cleanup is disabled until all devices are verified on the safe client rollout.');
 END IF;
 IF regexp_replace(upper(j.job_number),'[^0-9]','','g') ~ '^0*(7|11|12)$'
 OR EXISTS(SELECT 1 FROM briskers_cleanup_private.protected_entities t
   WHERE t.business_id=p_business_id AND t.entity_type='jobs' AND t.entity_id=p_job_id) THEN
   v_reasons:=array_append(v_reasons,'This Job is permanently protected.');
 END IF;
 IF j.status IS NULL OR j.status NOT IN ('open','pending_approval') OR j.completed_at IS NOT NULL
 OR j.authorization_number IS NOT NULL OR j.claim_number IS NOT NULL
 OR j.planned_hours IS DISTINCT FROM 0 THEN
   v_reasons:=array_append(v_reasons,'Job has protected status, authorization, claim or planned work.');
 END IF;
 SELECT coalesce(array_agg(id ORDER BY id),ARRAY[]::uuid[]) INTO v_doc_ids
 FROM briskers.sales_documents WHERE business_id=p_business_id AND job_id=p_job_id;
 v_ids:=array_prepend(p_job_id,v_doc_ids);
 FOR d IN SELECT * FROM briskers.sales_documents
   WHERE business_id=p_business_id AND job_id=p_job_id ORDER BY id LOOP
   v_documents:=v_documents||jsonb_build_array(jsonb_build_object(
     'id',d.id,'kind',d.kind,'number',d.document_number,'status',d.status,'total',d.total_amount));
   IF (d.kind='invoice' AND regexp_replace(d.document_number,'[^0-9]','','g') ~ '^0*(6331|6332|6334)$')
   OR (d.kind='estimate' AND regexp_replace(d.document_number,'[^0-9]','','g') ~ '^0*1997$')
   OR EXISTS(SELECT 1 FROM briskers_cleanup_private.protected_entities t
     WHERE t.business_id=p_business_id AND t.entity_type='sales_documents' AND t.entity_id=d.id) THEN
     v_reasons:=array_append(v_reasons,'Document '||d.id||' is permanently protected.');
   END IF;
   -- Deliberately narrow: draft is unpaid only after the dependency scan below.
   -- Even an empty string number is treated as numbered/unknown, not eligible.
   IF d.kind IS NULL OR d.kind NOT IN ('invoice','estimate') OR d.origin IS DISTINCT FROM 'native'
   OR d.status IS DISTINCT FROM 'draft' OR d.document_number IS NOT NULL
   OR d.issued_at IS NOT NULL OR d.published_at IS NOT NULL OR d.closed_at IS NOT NULL
   OR d.closed_by IS NOT NULL OR d.source_system IS NOT NULL OR d.source_reference IS NOT NULL
   OR d.source_imported_at IS NOT NULL OR d.legacy_status IS NOT NULL
   OR d.source_datetime_raw IS NOT NULL OR d.signature_required IS DISTINCT FROM false
   OR d.extended_warranty IS DISTINCT FROM false OR d.warranty_company_id IS NOT NULL
   OR d.warranty_approved_amount IS NOT NULL OR d.warranty_terminal_amount IS NOT NULL
   OR d.warranty_processor_fee IS NOT NULL OR d.warranty_net_applied IS NOT NULL
   OR d.authorization_number IS NOT NULL OR d.claim_number IS NOT NULL
   OR d.source_estimate_id IS NOT NULL OR d.credited_invoice_id IS NOT NULL
   OR d.source_metadata IS DISTINCT FROM '{}'::jsonb
   OR d.customer_id IS DISTINCT FROM j.customer_id
   OR d.vehicle_id IS DISTINCT FROM j.vehicle_id THEN
     v_reasons:=array_append(v_reasons,'Document '||d.id||' is numbered, non-draft, external, converted, or otherwise protected.');
   END IF;
 END LOOP;
 -- Only these owned children may be removed. Every other reference blocks.
 SELECT coalesce(array_agg(id),ARRAY[]::uuid[]) INTO v_safe_ids FROM (
   SELECT id FROM briskers.sales_document_lines WHERE business_id=p_business_id AND document_id=ANY(v_doc_ids)
   UNION ALL SELECT id FROM briskers.document_disclaimers WHERE business_id=p_business_id AND document_id=ANY(v_doc_ids)
   UNION ALL SELECT id FROM briskers.job_visits WHERE business_id=p_business_id AND job_id=p_job_id
   UNION ALL SELECT id FROM briskers.job_status_events WHERE business_id=p_business_id AND job_id=p_job_id
 ) s;
 v_ids:=v_ids||v_safe_ids;
 IF (SELECT count(*) FROM briskers.job_visits WHERE business_id=p_business_id AND job_id=p_job_id)>1
 OR EXISTS(SELECT 1 FROM briskers.job_visits WHERE business_id=p_business_id AND job_id=p_job_id
   AND (visit_number IS DISTINCT FROM 1 OR work_summary IS NOT NULL OR closed_at IS NOT NULL OR planned_hours IS DISTINCT FROM 0
     OR reason IS DISTINCT FROM 'Initial visit')) THEN
   v_reasons:=array_append(v_reasons,'Job has service visit or work history.');
 END IF;
 IF EXISTS(SELECT 1 FROM briskers.job_status_events WHERE business_id=p_business_id AND job_id=p_job_id
   AND ((from_status IS NULL AND to_status='open' AND note IS NOT DISTINCT FROM 'Job created')
     OR (from_status='open' AND to_status='pending_approval'
       AND note IS NOT DISTINCT FROM 'Job created for estimate preparation.')) IS DISTINCT FROM true) THEN
   v_reasons:=array_append(v_reasons,'Job has non-initial status history.');
 END IF;
 IF EXISTS(SELECT 1 FROM briskers.document_disclaimers WHERE business_id=p_business_id AND document_id=ANY(v_doc_ids)
   AND (signature_required IS DISTINCT FROM false OR authorization_id IS NOT NULL)) THEN
   v_reasons:=array_append(v_reasons,'A document disclaimer requires signature or has authorization history.');
 END IF;
 IF EXISTS(SELECT 1 FROM briskers.sales_document_lines WHERE business_id=p_business_id AND document_id=ANY(v_doc_ids)
   AND (source_row_number IS NOT NULL OR imported_unit_price IS NOT NULL)) THEN
   v_reasons:=array_append(v_reasons,'A document line has imported provenance.');
 END IF;
 -- Fixed signatures use byte order, independent of the database locale.
 -- In en_US, punctuation sorts differently, changing otherwise identical FK
 -- signatures. Canonical C ordering preserves the strict equality guard.
 -- A new column in a deletable table needs a new reviewed policy, even if NULL.
 FOR r IN SELECT * FROM (VALUES
   ('jobs','authorization_number:text:false:,business_id:uuid:true:,claim_number:text:false:,completed_at:timestamptz:false:,created_at:timestamptz:true:,created_by:uuid:false:,customer_id:uuid:true:,id:uuid:true:,job_number:text:true:,odometer_in:numeric:false:,planned_hours:numeric:true:,requested_work:text:false:,row_version:int8:true:,status:text:true:,title:text:true:,updated_at:timestamptz:true:,vehicle_id:uuid:false:'),
   ('sales_documents','authorization_number:text:false:,business_id:uuid:true:,claim_number:text:false:,closed_at:timestamptz:false:,closed_by:uuid:false:,created_at:timestamptz:true:,created_by:uuid:false:,credited_invoice_id:uuid:false:,currency_code:text:true:,customer_id:uuid:true:,customer_snapshot:jsonb:true:,document_date:date:false:,document_number:text:false:,due_date:date:false:,extended_warranty:bool:true:,id:uuid:true:,issued_at:timestamptz:false:,job_id:uuid:false:,kind:text:true:,legacy_discount:numeric:false:,legacy_shipping:numeric:false:,legacy_status:text:false:,memo:text:false:,net_amount:numeric:true:,origin:text:true:,published_at:timestamptz:false:,row_version:int8:true:,signature_required:bool:true:,source_datetime_raw:text:false:,source_estimate_id:uuid:false:,source_imported_at:timestamptz:false:,source_metadata:jsonb:true:,source_reference:text:false:,source_system:text:false:,status:text:true:,tax_amount:numeric:true:,total_amount:numeric:false:s,updated_at:timestamptz:true:,vehicle_id:uuid:false:,vehicle_snapshot:jsonb:true:,warranty_approved_amount:numeric:false:,warranty_company_id:uuid:false:,warranty_net_applied:numeric:false:,warranty_processor_fee:numeric:false:,warranty_surcharge_rate:numeric:true:,warranty_terminal_amount:numeric:false:'),
   ('sales_document_lines','business_id:uuid:true:,created_at:timestamptz:true:,created_by:uuid:false:,dealer_list_price:numeric:false:,description:text:false:,discount_method:text:false:,discount_timing:text:false:,discount_value:numeric:false:,document_id:uuid:true:,gross_amount:numeric:false:s,id:uuid:true:,imported_unit_price:numeric:false:,item_id:uuid:false:,line_kind:text:true:,name:text:true:,net_amount:numeric:true:,part_number:text:false:,position:int4:true:,price_checked_at:timestamptz:false:,price_source_name:text:false:,price_source_url:text:false:,price_verification_confidence:text:false:,price_verification_note:text:false:,price_verification_status:text:true:,pricing_unit:text:false:,quantity:numeric:true:,row_version:int8:true:,source_row_number:int8:false:,tax_amount:numeric:true:,tax_rate:numeric:true:,unit_price:numeric:true:,updated_at:timestamptz:true:'),
   ('document_disclaimers','authorization_id:uuid:false:,body:text:true:,business_id:uuid:true:,created_at:timestamptz:true:,created_by:uuid:false:,document_id:uuid:true:,id:uuid:true:,row_version:int8:true:,signature_required:bool:true:,template_id:uuid:false:,title:text:true:,updated_at:timestamptz:true:'),
   ('job_visits','business_id:uuid:true:,closed_at:timestamptz:false:,created_at:timestamptz:true:,created_by:uuid:false:,id:uuid:true:,job_id:uuid:true:,opened_at:timestamptz:true:,planned_hours:numeric:true:,reason:text:false:,row_version:int8:true:,updated_at:timestamptz:true:,visit_number:int4:true:,work_summary:text:false:'),
   ('job_status_events','business_id:uuid:true:,changed_at:timestamptz:true:,changed_by:uuid:false:,from_status:text:false:,id:uuid:true:,job_id:uuid:true:,note:text:false:,to_status:text:true:')
 ) s(table_name,expected_columns) LOOP
   v_expected:=string_to_array(r.expected_columns,',');
   SELECT array_agg(a.attname::text||':'||pt.typname||':'||a.attnotnull::text||':'||a.attgenerated::text ORDER BY a.attname::text COLLATE "C") INTO v_actual
   FROM pg_attribute a JOIN pg_type pt ON pt.oid=a.atttypid JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='briskers' AND c.relname=r.table_name AND a.attnum>0 AND NOT a.attisdropped;
   IF v_actual IS DISTINCT FROM v_expected THEN
     v_reasons:=array_append(v_reasons,'Unreviewed schema for '||r.table_name||'; cleanup blocked.');
   END IF;
 END LOOP;
 -- Constraint shape on every deletable table is pinned as well. A new or
 -- altered FK/unique key requires a reviewed migration, even with no matches.
 FOR r IN SELECT * FROM (VALUES
   ('jobs','FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT|FOREIGN KEY (business_id, customer_id) REFERENCES briskers.customers(business_id, id) ON DELETE RESTRICT|FOREIGN KEY (business_id, status) REFERENCES briskers.job_statuses(business_id, code) ON DELETE RESTRICT|FOREIGN KEY (business_id, vehicle_id) REFERENCES briskers.vehicles(business_id, id) ON DELETE RESTRICT|PRIMARY KEY (id)|UNIQUE (business_id, id)|UNIQUE (business_id, job_number)'),
   ('sales_documents','FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT|FOREIGN KEY (business_id, credited_invoice_id) REFERENCES briskers.sales_documents(business_id, id) ON DELETE RESTRICT|FOREIGN KEY (business_id, customer_id) REFERENCES briskers.customers(business_id, id) ON DELETE RESTRICT|FOREIGN KEY (business_id, job_id) REFERENCES briskers.jobs(business_id, id) ON DELETE RESTRICT|FOREIGN KEY (business_id, source_estimate_id) REFERENCES briskers.sales_documents(business_id, id) ON DELETE RESTRICT|FOREIGN KEY (business_id, vehicle_id) REFERENCES briskers.vehicles(business_id, id) ON DELETE RESTRICT|FOREIGN KEY (warranty_company_id) REFERENCES briskers.warranty_companies(id) ON DELETE SET NULL|PRIMARY KEY (id)|UNIQUE (business_id, id)'),
   ('sales_document_lines','FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE RESTRICT|FOREIGN KEY (business_id, document_id) REFERENCES briskers.sales_documents(business_id, id) ON DELETE RESTRICT|FOREIGN KEY (business_id, item_id) REFERENCES briskers.catalog_items(business_id, id) ON DELETE RESTRICT|PRIMARY KEY (id)|UNIQUE (business_id, document_id, "position")|UNIQUE (business_id, id)'),
   ('document_disclaimers','FOREIGN KEY (authorization_id) REFERENCES briskers.authorizations(id) ON DELETE SET NULL|FOREIGN KEY (business_id) REFERENCES briskers.businesses(id) ON DELETE CASCADE|FOREIGN KEY (document_id) REFERENCES briskers.sales_documents(id) ON DELETE CASCADE|FOREIGN KEY (template_id) REFERENCES briskers.disclaimer_templates(id) ON DELETE SET NULL|PRIMARY KEY (id)'),
   ('job_visits','FOREIGN KEY (business_id, job_id) REFERENCES briskers.jobs(business_id, id) ON DELETE RESTRICT|PRIMARY KEY (id)|UNIQUE (business_id, id)|UNIQUE (business_id, job_id, visit_number)'),
   ('job_status_events','FOREIGN KEY (business_id, job_id) REFERENCES briskers.jobs(business_id, id) ON DELETE RESTRICT|PRIMARY KEY (id)|UNIQUE (business_id, id)')
 ) q(table_name,expected_constraints) LOOP
   SELECT string_agg(pg_get_constraintdef(c.oid),'|' ORDER BY pg_get_constraintdef(c.oid) COLLATE "C") INTO v_schema
   FROM pg_constraint c WHERE c.conrelid=to_regclass('briskers.'||r.table_name) AND c.contype IN ('p','u','f');
   IF v_schema IS DISTINCT FROM r.expected_constraints THEN
     v_reasons:=array_append(v_reasons,'Unreviewed constraints for '||r.table_name||'; cleanup blocked.');
   END IF;
 END LOOP;
 -- Scan every briskers base table, including JSON payloads, idempotency ledgers,
 -- outboxes, legacy links, and future tables. Also scan any external-schema FK
 -- referencing a deletable table. UUID matches are deliberately conservative.
 FOR r IN SELECT DISTINCT n.nspname,c.relname,c.oid
   FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE c.relkind IN ('r','p') AND (n.nspname='briskers' OR c.oid IN (
     SELECT conrelid FROM pg_constraint WHERE contype='f' AND confrelid IN (
       'briskers.jobs'::regclass,'briskers.sales_documents'::regclass,
       'briskers.sales_document_lines'::regclass,'briskers.document_disclaimers'::regclass,
       'briskers.job_visits'::regclass,'briskers.job_status_events'::regclass)))
   ORDER BY n.nspname,c.relname,c.oid LOOP
   EXECUTE format('SELECT coalesce(jsonb_agg(x ORDER BY x::text COLLATE "C"),''[]''::jsonb) FROM
     (SELECT to_jsonb(t) x FROM %I.%I t WHERE EXISTS
       (SELECT 1 FROM unnest($1) q(id) WHERE strpos(replace(lower(to_jsonb(t)::text),''-'',''''),replace(q.id::text,''-'',''''))>0)) a',r.nspname,r.relname)
   INTO v_rows USING v_ids;
   v_count:=jsonb_array_length(v_rows);
   v_dependencies:=v_dependencies||jsonb_build_object(r.nspname||'.'||r.relname,v_count);
   -- Retain sync history; it is the existing Job deletion feed.
   IF r.nspname='briskers' AND r.relname='sync_job_changes' THEN CONTINUE; END IF;
   v_state:=v_state||jsonb_build_object(r.nspname||'.'||r.relname,v_rows);
   IF r.nspname='briskers' AND r.relname=ANY(ARRAY['jobs','sales_documents','sales_document_lines',
       'document_disclaimers','job_visits','job_status_events']) THEN
     SELECT count(*) INTO v_bad FROM jsonb_array_elements(v_rows) x
     WHERE x->>'business_id' IS DISTINCT FROM p_business_id::text
       OR NOT coalesce((x->>'id')::uuid=ANY(v_ids),false);
   ELSE v_bad:=v_count;
   END IF;
   IF v_bad>0 THEN
     v_reasons:=array_append(v_reasons,'Protected or external dependency: '||r.nspname||'.'||r.relname||' ('||v_bad||').');
   END IF;
 END LOOP;
 SELECT string_agg(x,'|' ORDER BY x COLLATE "C") INTO v_schema FROM (
   SELECT c.conrelid::regclass::text||':'||pg_get_constraintdef(c.oid) x FROM pg_constraint c
   WHERE c.connamespace='briskers'::regnamespace
 ) s;
 RETURN jsonb_build_object('schema_version',1,'business_id',p_business_id,'job_id',p_job_id,
   'job_number',j.job_number,'rollout_enabled',v_enabled,'can_delete',cardinality(v_reasons)=0,
   'blocked_reasons',to_jsonb(v_reasons),'documents',v_documents,'dependencies',v_dependencies,
   'fingerprint',md5(jsonb_build_object('rows',v_state,'schema',v_schema,'enabled',v_enabled,
     'reasons',v_reasons,'actor',auth.uid())::text));
END $f$;

CREATE FUNCTION public.briskers_test_job_cleanup_preview_v1(p_business_id uuid,p_job_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $f$
 SELECT briskers_cleanup_private.preview(p_business_id,p_job_id)
$f$;

CREATE FUNCTION public.briskers_test_job_cleanup_execute_v1(
 p_business_id uuid,p_job_id uuid,p_expected_fingerprint text,p_test_confirmation text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $f$
DECLARE v_plan jsonb; v_docs uuid[]; v_audit uuid; r record; v_count bigint;
BEGIN
 IF auth.uid() IS NULL OR briskers.is_owner(p_business_id) IS DISTINCT FROM true THEN
   RAISE EXCEPTION 'Owner access required' USING ERRCODE='42501';
 END IF;
 IF current_setting('transaction_isolation') <> 'read committed' THEN
   RAISE EXCEPTION 'Cleanup requires a fresh READ COMMITTED transaction' USING ERRCODE='40001';
 END IF;
 -- Do not take global locks for a disabled rollout or malformed request.
 IF NOT coalesce((SELECT enabled FROM briskers_cleanup_private.rollout WHERE business_id=p_business_id),false) THEN
   RAISE EXCEPTION 'Cleanup rollout is disabled' USING ERRCODE='55000';
 END IF;
 -- The active RPC statement timer must already be armed by the caller/API.
 -- Changing statement_timeout inside this function cannot bound that statement.
 -- Supabase authenticated/authenticator were verified configured to 8s.
 IF extract(epoch FROM current_setting('statement_timeout')::interval)<=0
 OR extract(epoch FROM current_setting('statement_timeout')::interval)>15 THEN
   RAISE EXCEPTION 'Cleanup requires a preconfigured request timeout of at most 15 seconds' USING ERRCODE='55000';
 END IF;
 IF p_expected_fingerprint IS NULL OR p_expected_fingerprint !~ '^[0-9a-f]{32}$'
 OR p_test_confirmation IS NULL THEN
   RAISE EXCEPTION 'Fresh preview and explicit test confirmation required' USING ERRCODE='22023';
 END IF;
 PERFORM set_config('lock_timeout','3s',true);
 -- Lock all scanned data tables in a deterministic order. No row/soft-reference
 -- can appear between the locked preview and deletion. Ordinary readers continue.
 FOR r IN SELECT DISTINCT n.nspname,c.relname,c.oid
   FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE c.relkind IN ('r','p') AND (n.nspname IN ('briskers','briskers_cleanup_private') OR c.oid IN (
     SELECT conrelid FROM pg_constraint WHERE contype='f' AND confrelid IN (
       'briskers.jobs'::regclass,'briskers.sales_documents'::regclass,
       'briskers.sales_document_lines'::regclass,'briskers.document_disclaimers'::regclass,
       'briskers.job_visits'::regclass,'briskers.job_status_events'::regclass)))
   ORDER BY n.nspname,c.relname,c.oid LOOP
   EXECUTE format('LOCK TABLE %I.%I IN SHARE ROW EXCLUSIVE MODE',r.nspname,r.relname);
 END LOOP;
 v_plan:=briskers_cleanup_private.preview(p_business_id,p_job_id);
 IF v_plan->>'fingerprint' IS DISTINCT FROM p_expected_fingerprint THEN
   RAISE EXCEPTION 'Cleanup preview changed; review a fresh preview' USING ERRCODE='40001';
 END IF;
 IF v_plan->>'can_delete' IS DISTINCT FROM 'true' THEN
   RAISE EXCEPTION 'Cleanup blocked: %',v_plan->'blocked_reasons' USING ERRCODE='55000';
 END IF;
 IF p_test_confirmation IS DISTINCT FROM 'DELETE TEST '||(v_plan->>'job_number') THEN
   RAISE EXCEPTION 'Exact test-only confirmation does not match this Job' USING ERRCODE='22023';
 END IF;
 SELECT coalesce(array_agg((x->>'id')::uuid ORDER BY x->>'id'),ARRAY[]::uuid[])
 INTO v_docs FROM jsonb_array_elements(v_plan->'documents') x;
 INSERT INTO briskers_cleanup_private.audit(business_id,job_id,actor_user_id,fingerprint,preview)
 VALUES(p_business_id,p_job_id,auth.uid(),p_expected_fingerprint,v_plan) RETURNING id INTO v_audit;
 INSERT INTO briskers_cleanup_private.identity_registry(entity_type,entity_id,business_id,deleted)
 SELECT 'jobs',p_job_id,p_business_id,true
 UNION ALL SELECT 'sales_documents',x,p_business_id,true FROM unnest(v_docs) x
 ON CONFLICT(entity_type,entity_id) DO UPDATE SET deleted=true;
 INSERT INTO briskers_cleanup_private.tombstones(business_id,entity_type,entity_id,job_id,audit_id)
 VALUES(p_business_id,'jobs',p_job_id,p_job_id,v_audit);
 INSERT INTO briskers_cleanup_private.tombstones(business_id,entity_type,entity_id,job_id,audit_id)
 SELECT p_business_id,'sales_documents',x,p_job_id,v_audit FROM unnest(v_docs) x;
 DELETE FROM briskers.document_disclaimers WHERE business_id=p_business_id AND document_id=ANY(v_docs);
 DELETE FROM briskers.sales_document_lines WHERE business_id=p_business_id AND document_id=ANY(v_docs);
 DELETE FROM briskers.sales_documents WHERE business_id=p_business_id AND id=ANY(v_docs) AND job_id=p_job_id;
 GET DIAGNOSTICS v_count=ROW_COUNT;
 IF v_count<>cardinality(v_docs) THEN RAISE EXCEPTION 'Document set changed' USING ERRCODE='40001'; END IF;
 DELETE FROM briskers.job_visits WHERE business_id=p_business_id AND job_id=p_job_id;
 DELETE FROM briskers.job_status_events WHERE business_id=p_business_id AND job_id=p_job_id;
 DELETE FROM briskers.jobs WHERE business_id=p_business_id AND id=p_job_id;
 GET DIAGNOSTICS v_count=ROW_COUNT;
 IF v_count<>1 THEN RAISE EXCEPTION 'Job set changed' USING ERRCODE='40001'; END IF;
 -- Existing trigger already queues DELETE; explicit event is harmless and makes
 -- this contract independent of trigger naming. History is intentionally retained.
 INSERT INTO briskers.sync_job_changes(business_id,job_id,reason)
 VALUES(p_business_id,p_job_id,'owner_test_cleanup:DELETE');
 RETURN jsonb_build_object('schema_version',1,'business_id',p_business_id,'job_id',p_job_id,
   'deleted_job_id',p_job_id,'deleted_document_ids',to_jsonb(v_docs),'audit_id',v_audit);
END $f$;

CREATE FUNCTION public.briskers_test_job_cleanup_tombstones_v1(p_business_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $f$
BEGIN
 IF auth.uid() IS NULL OR briskers.is_member(p_business_id) IS DISTINCT FROM true THEN
   RAISE EXCEPTION 'Business access denied' USING ERRCODE='42501';
 END IF;
 -- Existing Job sync permits business members, including mechanics. UUID-only
 -- tombstones must reach them too, so pending local media is preserved on cleanup.
 -- Permanent full list avoids deletion cursor gaps and bootstrap resurrection.
 -- Only IDs are returned; no document details or audit contents are exposed.
 RETURN jsonb_build_object('schema_version',1,'business_id',p_business_id,
   'deleted_job_ids',coalesce((SELECT jsonb_agg(entity_id ORDER BY entity_id)
     FROM briskers_cleanup_private.tombstones WHERE business_id=p_business_id AND entity_type='jobs'),'[]'::jsonb),
   'deleted_document_ids',coalesce((SELECT jsonb_agg(entity_id ORDER BY entity_id)
     FROM briskers_cleanup_private.tombstones WHERE business_id=p_business_id AND entity_type='sales_documents'),'[]'::jsonb));
END $f$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA briskers_cleanup_private FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.briskers_test_job_cleanup_preview_v1(uuid,uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.briskers_test_job_cleanup_execute_v1(uuid,uuid,text,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.briskers_test_job_cleanup_tombstones_v1(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.briskers_test_job_cleanup_preview_v1(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.briskers_test_job_cleanup_execute_v1(uuid,uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.briskers_test_job_cleanup_tombstones_v1(uuid) TO authenticated;
COMMIT;

-- Separate reviewed rollout enable step, NEVER executed by this migration:
-- After every device is verified upgraded and its offline work reviewed/synced,
-- a trusted administrator may INSERT the selected business into the private
-- rollout table with enabled=true, devices_verified_at=clock_timestamp(), and
-- reviewed_by=<verified owner UUID>. No client endpoint can set this gate.
-- A successful preview never authorizes any deletion by itself.

-- Exact operator procedure (psql variables are supplied only after review):
-- 1. Verify every active/offline device has the tombstone-aware build; reconcile
--    pending outboxes/media on each device and record that rollout evidence.
-- 2. Obtain explicit rollout-enable approval for the selected business.
-- 3. As a trusted database administrator, run this separate transaction:
-- BEGIN;
-- INSERT INTO briskers_cleanup_private.rollout
--   (business_id,enabled,devices_verified_at,reviewed_by)
-- VALUES (:'business_id'::uuid,true,clock_timestamp(),:'owner_user_id'::uuid)
-- ON CONFLICT (business_id) DO UPDATE
-- SET enabled=EXCLUDED.enabled,devices_verified_at=EXCLUDED.devices_verified_at,
--     reviewed_by=EXCLUDED.reviewed_by;
-- COMMIT;
-- 4. Verify the latest rollout_audit row and read-only cleanup preview show
--    rollout_enabled=true. This enables UI action-time confirmation only;
--    it neither marks any Job as test data nor authorizes any cleanup invocation.
-- To disable safely, a reviewed administrator sets enabled=false; that change
-- is also recorded by rollout_audit. Never purge the registry or tombstones.
