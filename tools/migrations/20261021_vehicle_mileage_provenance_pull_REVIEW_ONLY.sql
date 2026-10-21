-- Review-only; deploy AFTER mileage_schema_version and vehicle source
-- columns exist. Preserve existing permission checks, contacts, key-password
-- controls, pagination, and customer-level incremental pull behavior.
-- Only adds two nullable output keys to vehicle bundles.
CREATE OR REPLACE FUNCTION briskers.sync_customer_bundle_v1(p_business_id uuid, p_customer_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  c briskers.customers;
  v_contacts jsonb := '[]'::jsonb;
  v_vehicles jsonb := '[]'::jsonb;
  v_list_email text;
  v_list_phone text;
begin
  if not briskers.can(p_business_id,'customers.read') then return null; end if;

  select * into c from briskers.customers
  where business_id=p_business_id and id=p_customer_id and active;
  if not found then return null; end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'kind',cc.kind,'label',cc.label,'value',cc.value,'primary',cc.is_primary
    ) order by cc.is_primary desc,cc.created_at
  ),'[]'::jsonb)
  into v_contacts
  from briskers.customer_contacts cc
  where cc.business_id=p_business_id and cc.customer_id=p_customer_id;

  select cc.value into v_list_email
  from briskers.customer_contacts cc
  where cc.business_id=p_business_id and cc.customer_id=p_customer_id and cc.kind='email'
  order by cc.is_primary desc,cc.created_at limit 1;

  select cc.value into v_list_phone
  from briskers.customer_contacts cc
  where cc.business_id=p_business_id and cc.customer_id=p_customer_id and cc.kind='phone'
  order by cc.is_primary desc,cc.created_at limit 1;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id',v.id,'year',v.year,'make',v.make,'model',v.model,
      'vin',v.vin_raw,'license_plate',v.license_plate,
      'license_state',v.license_state,'mileage',v.odometer,
      'mileage_recorded_date',v.odometer_source_date,
      'mileage_source_invoice_id',v.odometer_source_invoice_id,
      'color',v.color,
      'key_password',vp.key_password_raw,
      'updated_at',v.updated_at,'row_version',v.row_version,
      'is_primary',vc.is_primary
    ) order by v.year desc nulls last,v.make,v.model,v.id
  ),'[]'::jsonb)
  into v_vehicles
  from briskers.vehicle_customers vc
  join briskers.vehicles v
    on v.business_id=vc.business_id and v.id=vc.vehicle_id
  left join briskers.vehicle_private vp
    on vp.business_id=v.business_id and vp.vehicle_id=v.id
  where vc.business_id=p_business_id and vc.customer_id=p_customer_id
    and (vc.valid_until is null or vc.valid_until>=current_date)
    and v.active;

  return jsonb_build_object(
    'customer',jsonb_build_object(
      'id',c.id,'name',c.display_name,'display_name',c.display_name,
      'is_company',c.is_company,'email',c.email,'phone',c.phone_raw,
      'list_email',coalesce(v_list_email,c.email),
      'list_phone',coalesce(v_list_phone,c.phone_raw),
      'billing_address',c.billing_address,'taxable',c.taxable,
      'problem_flag',c.problem_flag,
      'problem_flag_note',coalesce(c.problem_flag_note,''),
      'created_at',c.created_at,'updated_at',c.updated_at,'row_version',c.row_version
    ),
    'contacts',v_contacts,'vehicles',v_vehicles
  );
end $function$
;
