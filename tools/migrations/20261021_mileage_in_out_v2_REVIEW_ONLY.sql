-- BRISKERS MILEAGE V2 — REVIEW ONLY. DO NOT APPLY TO BRISKERS DEV/PRODUCTION.
-- Requires isolated PostgreSQL tests with the currently deployed functions,
-- multi-device offline replay tests, and Owner approval before deployment.
-- Existing odometer_in fields and imported PDFs remain unchanged.
BEGIN;

ALTER TABLE briskers.sales_documents
  ADD COLUMN IF NOT EXISTS mileage_schema_version smallint;
UPDATE briskers.sales_documents
SET mileage_schema_version = 1
WHERE mileage_schema_version IS NULL;
ALTER TABLE briskers.sales_documents
  ALTER COLUMN mileage_schema_version SET DEFAULT 2,
  ALTER COLUMN mileage_schema_version SET NOT NULL;
ALTER TABLE briskers.sales_documents
  ADD COLUMN IF NOT EXISTS odometer_out numeric;
ALTER TABLE briskers.vehicles
  ADD COLUMN IF NOT EXISTS odometer_source_invoice_id uuid,
  ADD COLUMN IF NOT EXISTS odometer_source_date date,
  ADD COLUMN IF NOT EXISTS odometer_read_at timestamptz;

-- An already-populated profile retains its existing registration mileage.
-- No existing sales document gets a fabricated departure reading.
ALTER TABLE briskers.sales_documents
  ADD CONSTRAINT sales_documents_odometer_out_v2_valid
  CHECK (odometer_out IS NULL OR
    (odometer_out >= 0 AND odometer_out <= 9999999
       AND odometer_out = trunc(odometer_out)));
ALTER TABLE briskers.sales_documents
  ADD CONSTRAINT sales_documents_mileage_schema_version_valid
  CHECK (mileage_schema_version IN (1,2));

-- Internal-only, same-business, completed-job update. This intentionally
-- does not delete data, backfill history, or decrease Current Mileage.
CREATE OR REPLACE FUNCTION briskers.apply_completed_invoice_mileage_v2(
  p_business_id uuid, p_invoice_id uuid
) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  d briskers.sales_documents;
  j briskers.jobs;
  v briskers.vehicles;
  target_id uuid;
  read_date date;
BEGIN
  SELECT * INTO d FROM briskers.sales_documents
  WHERE business_id=p_business_id AND id=p_invoice_id
    AND kind='invoice' AND origin='native'
    AND status <> 'void' AND mileage_schema_version=2
    AND odometer_out IS NOT NULL;
  IF NOT FOUND THEN RETURN false; END IF;

  SELECT * INTO j FROM briskers.jobs
  WHERE business_id=p_business_id AND id=d.job_id
    AND status='completed';
  IF NOT FOUND THEN RETURN false; END IF;
  target_id := coalesce(d.vehicle_id,j.vehicle_id);
  IF target_id IS NULL OR
     (j.vehicle_id IS NOT NULL AND j.vehicle_id <> target_id)
  THEN RETURN false; END IF;

  SELECT * INTO v FROM briskers.vehicles
  WHERE business_id=p_business_id AND id=target_id AND active
  FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;

  read_date := coalesce(d.document_date,d.created_at::date);
  -- A late offline upload, old invoice edit, or lower reading must not
  -- roll back a newer Current Mileage entry.
  IF (v.odometer_source_date IS NOT NULL AND
      read_date < v.odometer_source_date) OR
     (v.odometer IS NOT NULL AND d.odometer_out < v.odometer)
  THEN RETURN false; END IF;

  UPDATE briskers.vehicles
  SET odometer=d.odometer_out, odometer_unit='mi',
      odometer_source_invoice_id=d.id,
      odometer_source_date=read_date,
      odometer_read_at=clock_timestamp(),
      updated_at=clock_timestamp(),
      row_version=row_version+1
  WHERE business_id=p_business_id AND id=target_id;
  RETURN true;
END $fn$;
REVOKE ALL ON FUNCTION briskers.apply_completed_invoice_mileage_v2(uuid,uuid)
  FROM PUBLIC, anon, authenticated;

-- Applies when repair work is marked completed, independent of payment.
CREATE OR REPLACE FUNCTION briskers.completed_job_mileage_trigger_v2()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $fn$
DECLARE invoice_id uuid;
BEGIN
  IF NEW.status IS DISTINCT FROM 'completed' OR
     OLD.status IS NOT DISTINCT FROM NEW.status
  THEN RETURN NEW; END IF;
  SELECT d.id INTO invoice_id
  FROM briskers.sales_documents d
  WHERE d.business_id=NEW.business_id AND d.job_id=NEW.id
    AND d.kind='invoice' AND d.origin='native'
    AND d.status <> 'void' AND d.mileage_schema_version=2
    AND d.odometer_out IS NOT NULL
  ORDER BY coalesce(d.document_date,d.created_at::date) DESC,
           d.created_at DESC,d.id DESC
  LIMIT 1;
  IF invoice_id IS NOT NULL THEN
    PERFORM briskers.apply_completed_invoice_mileage_v2(
      NEW.business_id,invoice_id);
  END IF;
  RETURN NEW;
END $fn$;
REVOKE ALL ON FUNCTION briskers.completed_job_mileage_trigger_v2()
  FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS briskers_completed_job_mileage_v2 ON briskers.jobs;
CREATE TRIGGER briskers_completed_job_mileage_v2
AFTER UPDATE OF status ON briskers.jobs
FOR EACH ROW EXECUTE FUNCTION briskers.completed_job_mileage_trigger_v2();

-- Owner and Secretary with invoice-edit permissions can record departure
-- mileage; changes must not rewrite historical arrival odometers.
CREATE OR REPLACE FUNCTION public.briskers_save_invoice_mileage_out_v1(
  p_business_id uuid, p_document_id uuid,
  p_expected_version bigint, p_mileage_out numeric
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE d briskers.sales_documents;
BEGIN
  PERFORM briskers.require_permission(p_business_id,'invoices.edit');
  IF p_mileage_out IS NOT NULL AND
     (p_mileage_out < 0 OR p_mileage_out > 9999999 OR
      p_mileage_out <> trunc(p_mileage_out)) THEN
    RAISE EXCEPTION 'Invalid departure mileage' USING ERRCODE='22023';
  END IF;
  SELECT * INTO d FROM briskers.sales_documents
  WHERE business_id=p_business_id AND id=p_document_id FOR UPDATE;
  IF NOT FOUND OR d.kind <> 'invoice' OR d.origin <> 'native' OR
     d.status='void' OR d.mileage_schema_version <> 2 THEN
    RAISE EXCEPTION 'Invoice is not eligible for departure mileage edit'
      USING ERRCODE='55000';
  END IF;
  IF d.row_version IS DISTINCT FROM p_expected_version THEN
    RAISE EXCEPTION 'Invoice changed elsewhere' USING ERRCODE='40001';
  END IF;
  UPDATE briskers.sales_documents
  SET odometer_out=p_mileage_out,
      updated_at=clock_timestamp(),row_version=row_version+1
  WHERE business_id=p_business_id AND id=p_document_id;
  IF p_mileage_out IS NOT NULL THEN
    PERFORM briskers.apply_completed_invoice_mileage_v2(
      p_business_id,p_document_id);
  END IF;
  RETURN jsonb_build_object(
    'document_id',p_document_id,'mileage_out',p_mileage_out);
END $fn$;
REVOKE ALL ON FUNCTION public.briskers_save_invoice_mileage_out_v1(
  uuid,uuid,bigint,numeric) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.briskers_save_invoice_mileage_out_v1(
  uuid,uuid,bigint,numeric) TO authenticated;

-- Keep the existing v4 API intact for current phones. Future clients call
-- v5; old invoice data remains unlabeled legacy Mileage, not false Out.
CREATE OR REPLACE FUNCTION public.briskers_document_detail_v5(
  p_business_id uuid,p_document_id uuid
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  base_detail jsonb;
  d briskers.sales_documents;
  job_in numeric;
BEGIN
  base_detail := public.briskers_document_detail_v4(
    p_business_id,p_document_id);
  SELECT * INTO d FROM briskers.sales_documents
    WHERE business_id=p_business_id AND id=p_document_id;
  IF NOT FOUND OR d.mileage_schema_version <> 2 THEN
    RETURN base_detail;
  END IF;
  SELECT coalesce(i.odometer,j.odometer_in) INTO job_in
  FROM briskers.jobs j
  LEFT JOIN briskers.job_pre_inspections i
    ON i.business_id=j.business_id AND i.job_id=j.id
  WHERE j.business_id=p_business_id AND j.id=d.job_id;
  RETURN base_detail || jsonb_build_object(
    'mileage_schema_version',2,
    'mileage_in',job_in,
    'mileage_out',d.odometer_out
  );
END $fn$;
REVOKE ALL ON FUNCTION public.briskers_document_detail_v5(uuid,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.briskers_document_detail_v5(uuid,uuid)
  TO authenticated;

COMMIT;

-- Still required before production: correct invoice customer/vehicle
-- authorization and conflict tests; offline idempotency + latest-by-date race
-- tests; no new page caches should lose v5 fields. Review trigger interactions
-- with the installed job completion and invoice revision functions.
