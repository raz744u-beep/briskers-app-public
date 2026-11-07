CREATE OR REPLACE FUNCTION public.briskers_issue_document(p_business_id uuid, p_document_id uuid, p_expected_version bigint, p_document_date date DEFAULT CURRENT_DATE)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  d briskers.sales_documents;
  cust jsonb;
  vehicle jsonb;
  num text;
begin
  select * into d
  from briskers.sales_documents
  where business_id=p_business_id and id=p_document_id
  for update;

  if not found then
    raise exception 'Document not found' using errcode='P0002';
  end if;

  perform briskers.require_permission(
    p_business_id,
    case when d.kind='estimate' then 'estimates.create' else 'invoices.create' end
  );

  if d.origin<>'native' or d.status='void' then
    raise exception 'Document cannot be published' using errcode='55000';
  end if;
  if d.row_version<>p_expected_version then
    raise exception 'Document changed; reload before publishing' using errcode='40001';
  end if;
  if not exists(
    select 1 from briskers.sales_document_lines
    where business_id=p_business_id and document_id=p_document_id
  ) then
    raise exception 'Cannot publish a document with no lines' using errcode='23514';
  end if;

  perform briskers.recalculate_native_document(p_business_id,p_document_id);

  select jsonb_build_object(
    'name',c.display_name,
    'email',c.email,
    'phone',c.phone_raw,
    'billing_address',c.billing_address
  )
  into cust
  from briskers.customers c
  where c.business_id=p_business_id and c.id=d.customer_id;

  select jsonb_build_object(
    'year',v.year,
    'make',v.make,
    'model',v.model,
    'vin',v.vin_raw,
    'license_plate',v.license_plate,
    'color',v.color,
    'odometer',coalesce(j.odometer_in,v.odometer),
    'odometer_unit',v.odometer_unit
  )
  into vehicle
  from briskers.jobs j
  join briskers.vehicles v
    on v.business_id=j.business_id and v.id=j.vehicle_id
  where j.business_id=p_business_id and j.id=d.job_id;

  num:=coalesce(d.document_number,briskers.next_number(p_business_id,d.kind));

  update briskers.sales_documents
  set document_number=num,
      status=case when status='draft' then 'issued' else status end,
      document_date=coalesce(document_date,p_document_date),
      issued_at=coalesce(issued_at,clock_timestamp()),
      published_at=clock_timestamp(),
      customer_snapshot=coalesce(cust,'{}'::jsonb),
      vehicle_snapshot=coalesce(vehicle,'{}'::jsonb),
      updated_at=clock_timestamp(),
      row_version=row_version+1
  where business_id=p_business_id and id=p_document_id;

  return num;
end
$function$
;

CREATE OR REPLACE FUNCTION public.briskers_save_invoice_mileage_out_v1(p_business_id uuid, p_document_id uuid, p_expected_version bigint, p_mileage_out numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
     d.status='void' OR d.closed_at IS NOT NULL OR
     d.mileage_schema_version <> 2 THEN
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
END $function$
;

CREATE OR REPLACE FUNCTION public.briskers_sync_offline_appointment_delete(p_business_id uuid, p_appointment_id uuid, p_operation_id uuid, p_base_version bigint)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE op briskers.appointment_delete_operations; a briskers.appointments;
BEGIN
 IF NOT briskers.is_owner(p_business_id) THEN
  RAISE EXCEPTION 'Owner access required' USING ERRCODE='42501';
 END IF;
 IF p_operation_id IS NULL OR p_base_version IS NULL THEN
  RAISE EXCEPTION 'Missing operation ID or revision' USING ERRCODE='22023';
 END IF;
 INSERT INTO briskers.appointment_delete_operations
 (business_id,operation_id,appointment_id,base_version)
 VALUES(p_business_id,p_operation_id,p_appointment_id,p_base_version)
 ON CONFLICT(business_id,operation_id) DO NOTHING;
 SELECT * INTO STRICT op FROM briskers.appointment_delete_operations
 WHERE business_id=p_business_id AND operation_id=p_operation_id FOR UPDATE;
 IF op.appointment_id IS DISTINCT FROM p_appointment_id OR
    op.base_version IS DISTINCT FROM p_base_version THEN
  RAISE EXCEPTION 'Deletion key reused with changed request' USING ERRCODE='23505';
 END IF;
 IF op.completed_at IS NOT NULL THEN RETURN true; END IF;
 SELECT * INTO a FROM briskers.appointments
 WHERE business_id=p_business_id AND id=p_appointment_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Appointment missing or deleted by another operation' USING ERRCODE='40001'; END IF;
 IF a.row_version<>p_base_version THEN
  RAISE EXCEPTION 'Appointment changed on another device' USING ERRCODE='40001';
 END IF;
 PERFORM public.briskers_delete_appointment(p_business_id,p_appointment_id);
 UPDATE briskers.appointment_delete_operations SET completed_at=clock_timestamp()
 WHERE business_id=p_business_id AND operation_id=p_operation_id;
 RETURN true;
END $function$
;
