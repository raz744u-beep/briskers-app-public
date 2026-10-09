-- Quick invoices must create a linked shop job in the same transaction.
-- This replaces only the existing RPC; all invoice numbering and validation
-- are retained. The common create-job RPC maintains job visits/status events.
-- A failed job insertion rolls back the entire invoice creation.

CREATE OR REPLACE FUNCTION public.briskers_create_quick_invoice(
  p_business_id uuid,
  p_customer_id uuid,
  p_vehicle_id uuid DEFAULT NULL::uuid,
  p_document_date date DEFAULT CURRENT_DATE
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_id uuid;
  v_num text;
  v_job_id uuid;
BEGIN
  PERFORM briskers.require_permission(p_business_id, 'invoices.create');
  -- A quick invoice creates a job as part of the same authorized operation.
  PERFORM briskers.require_permission(p_business_id, 'jobs.create');

  IF NOT EXISTS (
    SELECT 1 FROM briskers.customers c
    WHERE c.business_id = p_business_id
      AND c.id = p_customer_id
      AND c.active
  ) THEN
    RAISE EXCEPTION 'Customer not found' USING ERRCODE = 'P0002';
  END IF;

  IF p_vehicle_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM briskers.vehicle_customers vc
    JOIN briskers.vehicles v
      ON v.business_id = vc.business_id AND v.id = vc.vehicle_id
    WHERE vc.business_id = p_business_id
      AND vc.customer_id = p_customer_id
      AND vc.vehicle_id = p_vehicle_id
      AND v.active
      AND (vc.valid_until IS NULL OR vc.valid_until >= CURRENT_DATE)
  ) THEN
    RAISE EXCEPTION 'Vehicle is not associated with selected customer'
      USING ERRCODE = '23514';
  END IF;

  v_num := briskers.next_number(p_business_id, 'invoice');
  v_job_id := public.briskers_create_job(
    p_business_id,
    p_customer_id,
    p_vehicle_id,
    'Invoice #' || v_num,
    'Created automatically from quick invoice #' || v_num
  );

  INSERT INTO briskers.sales_documents (
    business_id, kind, customer_id, vehicle_id, job_id,
    document_number, document_date, created_by
  ) VALUES (
    p_business_id, 'invoice', p_customer_id, p_vehicle_id, v_job_id,
    v_num, COALESCE(p_document_date, CURRENT_DATE), auth.uid()
  ) RETURNING id INTO v_id;

  RETURN v_id;
END;
$function$;
