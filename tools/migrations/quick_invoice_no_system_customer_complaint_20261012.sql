-- Quick-invoice bookkeeping is not a customer complaint.
-- Preserve job title and automatic job creation, but leave requested_work NULL.
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
    SELECT 1 FROM briskers.vehicle_customers vc
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
    NULL
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

-- Only remove the exact generated placeholder from J-11; leave all other
-- customer complaints and every related invoice record unchanged.
UPDATE briskers.jobs
SET requested_work = NULL,
    updated_at = clock_timestamp()
WHERE job_number = 'J-11'
  AND title = 'Invoice #6332'
  AND requested_work = 'Created automatically from quick invoice #6332'
  AND business_id = '93403e82-42b4-465c-b539-b5e127104f1b'::uuid;
