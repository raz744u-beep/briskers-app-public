-- Additive Owner-only synchronization endpoint; no existing rows are changed by installation.
-- Serializes against the existing employee settings writer, compares only edited
-- fields, and treats an already-applied patch as an idempotent acknowledgement.
CREATE OR REPLACE FUNCTION public.briskers_patch_employee_details_v1(
  p_business_id uuid,p_employee_id uuid,p_base jsonb,p_patch jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $function$
DECLARE
  current_detail jsonb;
  merged jsonb;
  k text;
  conflicts jsonb := '[]'::jsonb;
  changed boolean := false;
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS (
    SELECT 1 FROM briskers.memberships m WHERE m.business_id=p_business_id
    AND m.user_id=auth.uid() AND m.active AND m.role_code='owner'
  ) THEN RAISE EXCEPTION 'Owner access required' USING ERRCODE='42501'; END IF;
  PERFORM briskers.require_permission(p_business_id,'settings.manage');
  IF jsonb_typeof(p_base) IS DISTINCT FROM 'object' OR
     jsonb_typeof(p_patch) IS DISTINCT FROM 'object' OR p_patch='{}'::jsonb THEN
    RAISE EXCEPTION 'A non-empty explicit patch and baseline are required' USING ERRCODE='22023';
  END IF;
  IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_patch) f WHERE f NOT IN
    ('name','phone','email','address','position_id','compensation_enabled','payment_type','hourly_rate','weekly_rate','active')) THEN
    RAISE EXCEPTION 'Unsupported or protected employee field' USING ERRCODE='22023';
  END IF;
  PERFORM 1 FROM briskers.employees WHERE business_id=p_business_id AND id=p_employee_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Employee not found; no new profile created' USING ERRCODE='P0002'; END IF;
  current_detail:=public.briskers_employee_settings_detail(p_business_id,p_employee_id);
  FOR k IN SELECT jsonb_object_keys(p_patch) LOOP
    IF NOT (p_base ? k) OR NOT(current_detail ? k) THEN
      conflicts:=conflicts||jsonb_build_array(k);
    ELSIF current_detail->k IS NOT DISTINCT FROM p_patch->k THEN
      CONTINUE;
    ELSIF current_detail->k IS DISTINCT FROM p_base->k THEN
      conflicts:=conflicts||jsonb_build_array(k);
    ELSE changed:=true;
    END IF;
  END LOOP;
  IF conflicts<>'[]'::jsonb THEN RETURN jsonb_build_object('conflict',true,'fields',conflicts); END IF;
  merged:=current_detail||p_patch;
  IF changed THEN
    IF p_patch ?| array['payment_type','hourly_rate','weekly_rate','compensation_enabled'] THEN
      PERFORM public.briskers_save_employee_settings(p_business_id,p_employee_id,
        merged->>'name',merged->>'phone',merged->>'email',merged->>'address',
        (merged->>'position_id')::uuid,(merged->>'compensation_enabled')::boolean,
        merged->>'payment_type',(merged->>'hourly_rate')::numeric,
        (merged->>'weekly_rate')::numeric,(merged->>'active')::boolean,NULL);
    ELSE
      IF nullif(btrim(merged->>'name'),'') IS NULL THEN RAISE EXCEPTION 'Employee name required' USING ERRCODE='22023'; END IF;
      IF NOT EXISTS(SELECT 1 FROM briskers.employee_positions WHERE business_id=p_business_id AND id=(merged->>'position_id')::uuid) THEN
        RAISE EXCEPTION 'Valid position required' USING ERRCODE='22023';
      END IF;
      -- Contact-only edits must not append/reprice compensation history.
      UPDATE briskers.employees e SET display_name=merged->>'name',
        phone=nullif(merged->>'phone',''),email=nullif(merged->>'email',''),address=nullif(merged->>'address',''),
        position_id=(merged->>'position_id')::uuid,active=(merged->>'active')::boolean,
        updated_at=clock_timestamp(),row_version=e.row_version+1
      WHERE e.business_id=p_business_id AND e.id=p_employee_id;
    END IF;
  END IF;
  RETURN jsonb_build_object('conflict',false,'details',current_detail||p_patch);
END
$function$;
REVOKE ALL ON FUNCTION public.briskers_patch_employee_details_v1(uuid,uuid,jsonb,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.briskers_patch_employee_details_v1(uuid,uuid,jsonb,jsonb) TO authenticated;
