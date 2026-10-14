-- SOURCE ONLY. DO NOT DEPLOY OR ENABLE THE APK DELETION GATE.
-- Data-preserving, audited retirement contract: no entity rows are destroyed and no
-- numbers are reused. Deployment requires tombstone-aware read AND write RPCs,
-- conflict/replay checks on every device, and approved security review.
-- No grants are issued: even an installed candidate stays inaccessible.
BEGIN;
CREATE TABLE IF NOT EXISTS briskers.job_retirement_operations_v2 (
  business_id uuid NOT NULL,
  operation_id uuid NOT NULL,
  job_id uuid NOT NULL,
  actor_id uuid NOT NULL,
  expected_snapshot jsonb NOT NULL,
  receipt jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(business_id, operation_id),
  UNIQUE(business_id, job_id)
);
CREATE TABLE IF NOT EXISTS briskers.job_retirement_tombstones_v2 (
  business_id uuid NOT NULL,
  entity_kind text NOT NULL CHECK(entity_kind IN ('job','invoice')),
  entity_id uuid NOT NULL,
  operation_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(business_id,entity_kind,entity_id),
  FOREIGN KEY(business_id,operation_id)
    REFERENCES briskers.job_retirement_operations_v2(business_id,operation_id)
);
ALTER TABLE briskers.job_retirement_operations_v2 ENABLE ROW LEVEL SECURITY;
ALTER TABLE briskers.job_retirement_tombstones_v2 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON briskers.job_retirement_operations_v2 FROM PUBLIC, anon, authenticated;
REVOKE ALL ON briskers.job_retirement_tombstones_v2 FROM PUBLIC, anon, authenticated;

-- Immutable audit even if future application code accidentally tries to edit it.
CREATE OR REPLACE FUNCTION briskers.reject_retirement_audit_mutation_v2()
RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN RAISE EXCEPTION 'Retirement audit and tombstones are immutable'
  USING ERRCODE='55000'; END $$;
DROP TRIGGER IF EXISTS immutable_retirement_operations ON briskers.job_retirement_operations_v2;
CREATE TRIGGER immutable_retirement_operations BEFORE UPDATE OR DELETE
ON briskers.job_retirement_operations_v2 FOR EACH ROW
EXECUTE FUNCTION briskers.reject_retirement_audit_mutation_v2();
DROP TRIGGER IF EXISTS immutable_retirement_tombstones ON briskers.job_retirement_tombstones_v2;
CREATE TRIGGER immutable_retirement_tombstones BEFORE UPDATE OR DELETE
ON briskers.job_retirement_tombstones_v2 FOR EACH ROW
EXECUTE FUNCTION briskers.reject_retirement_audit_mutation_v2();

-- Dependency inventory supplied by an audited schema adapter, not the client.
-- The adapter MUST account for all FKs and semantic references, including
-- pending/posted/uncertain payments, expenses, attachments, visits, notes,
-- historical imports, estimates, reassignments, customer and vehicle ownership.
-- Intentionally absent until deployed-schema audit proves complete coverage.
-- An absent adapter raises an error; there is NO legacy cascade fallback.
CREATE OR REPLACE FUNCTION public.briskers_job_retirement_preview_v2(
  p_business_id uuid, p_job_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb;
BEGIN
  IF auth.uid() IS NULL OR briskers.is_owner(p_business_id) IS DISTINCT FROM true
  THEN RAISE EXCEPTION 'Owner access required' USING ERRCODE='42501'; END IF;
  IF to_regprocedure('briskers.job_retirement_verified_snapshot_v2(uuid,uuid)') IS NULL
  THEN RAISE EXCEPTION 'Audited retirement dependency adapter is not deployed'
    USING ERRCODE='55000'; END IF;
  EXECUTE 'SELECT briskers.job_retirement_verified_snapshot_v2($1,$2)'
    INTO result USING p_business_id,p_job_id;
  IF result->>'business_id' IS DISTINCT FROM p_business_id::text
     OR result->>'job_id' IS DISTINCT FROM p_job_id::text
     OR result->>'schema_version' IS DISTINCT FROM '2'
     OR jsonb_typeof(result->'invoices') IS DISTINCT FROM 'array'
     OR jsonb_typeof(result->'estimates_preserved') IS DISTINCT FROM 'array'
     OR result->>'inventory_complete' IS DISTINCT FROM 'true'
  THEN RAISE EXCEPTION 'Incomplete authoritative retirement inventory'
    USING ERRCODE='55000'; END IF;
  RETURN result;
END $$;

CREATE OR REPLACE FUNCTION public.briskers_job_retirement_execute_v2(
  p_business_id uuid, p_job_id uuid, p_operation_id uuid,
  p_expected_snapshot jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE prior briskers.job_retirement_operations_v2;
  current_snapshot jsonb; receipt jsonb; invoice jsonb;
BEGIN
  IF auth.uid() IS NULL OR briskers.is_owner(p_business_id) IS DISTINCT FROM true
  THEN RAISE EXCEPTION 'Owner access required' USING ERRCODE='42501'; END IF;
  IF p_operation_id IS NULL OR p_expected_snapshot IS NULL
  THEN RAISE EXCEPTION 'Operation ID and confirmed snapshot required'
    USING ERRCODE='22023'; END IF;
  -- Serialize duplicate/retried requests across users and devices. The adapter
  -- must additionally lock the job/document and dependency write paths.
  PERFORM pg_advisory_xact_lock(hashtextextended(p_business_id::text, 0));
  SELECT * INTO prior FROM briskers.job_retirement_operations_v2
    WHERE business_id=p_business_id AND operation_id=p_operation_id;
  IF FOUND THEN
    IF prior.job_id IS DISTINCT FROM p_job_id
       OR prior.expected_snapshot IS DISTINCT FROM p_expected_snapshot
    THEN RAISE EXCEPTION 'Operation ID reused for a different request'
      USING ERRCODE='22023'; END IF;
    RETURN prior.receipt;
  END IF;
  IF EXISTS(SELECT 1 FROM briskers.job_retirement_operations_v2
    WHERE business_id=p_business_id AND job_id=p_job_id)
  THEN RAISE EXCEPTION 'Job already retired; refresh authoritative state'
    USING ERRCODE='55000'; END IF;
  current_snapshot:=public.briskers_job_retirement_preview_v2(p_business_id,p_job_id);
  IF current_snapshot IS DISTINCT FROM p_expected_snapshot
  THEN RAISE EXCEPTION 'Job links changed; obtain a fresh preview and confirmation'
    USING ERRCODE='40001'; END IF;
  IF current_snapshot->>'can_retire' IS DISTINCT FROM 'true'
     OR current_snapshot->'blocked_reasons' IS DISTINCT FROM '[]'::jsonb
     OR current_snapshot->>'write_fences_verified' IS DISTINCT FROM 'true'
  THEN RAISE EXCEPTION 'Job has protected history or incomplete write fences'
    USING ERRCODE='55000'; END IF;
  receipt:=jsonb_build_object('schema_version',2,'business_id',p_business_id,
    'job_id',p_job_id,'operation_id',p_operation_id,
    'retired_invoice_ids',coalesce((SELECT jsonb_agg(x->>'id')
      FROM jsonb_array_elements(current_snapshot->'invoices') x),'[]'::jsonb),
    'estimates_preserved',current_snapshot->'estimates_preserved');
  INSERT INTO briskers.job_retirement_operations_v2
    (business_id,operation_id,job_id,actor_id,expected_snapshot,receipt)
    VALUES(p_business_id,p_operation_id,p_job_id,auth.uid(),current_snapshot,receipt);
  INSERT INTO briskers.job_retirement_tombstones_v2
    (business_id,entity_kind,entity_id,operation_id)
    VALUES(p_business_id,'job',p_job_id,p_operation_id);
  FOR invoice IN SELECT * FROM jsonb_array_elements(current_snapshot->'invoices') LOOP
    -- Defense in depth; adapter is never permission to remove financial history.
    IF invoice->>'business_id' IS DISTINCT FROM p_business_id::text
       OR invoice->>'job_id' IS DISTINCT FROM p_job_id::text
       OR nullif(invoice->>'id','') IS NULL
       OR invoice->>'kind' IS DISTINCT FROM 'invoice'
       OR invoice->>'origin' IS DISTINCT FROM 'native'
       OR invoice->>'status' IS DISTINCT FROM 'draft'
       OR invoice->>'has_financial_history' IS DISTINCT FROM 'false'
       OR invoice->>'has_pending_operations' IS DISTINCT FROM 'false'
       OR invoice->>'has_protected_history' IS DISTINCT FROM 'false'
    THEN RAISE EXCEPTION 'Protected linked invoice' USING ERRCODE='55000'; END IF;
    INSERT INTO briskers.job_retirement_tombstones_v2
      (business_id,entity_kind,entity_id,operation_id)
      VALUES(p_business_id,'invoice',(invoice->>'id')::uuid,p_operation_id);
  END LOOP;
  RETURN receipt;
END $$;
REVOKE ALL ON FUNCTION public.briskers_job_retirement_preview_v2(uuid,uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.briskers_job_retirement_execute_v2(uuid,uuid,uuid,jsonb)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION briskers.reject_retirement_audit_mutation_v2() FROM PUBLIC;
COMMIT;
