-- Additive metadata for the existing employee identity. Install before the app
-- starts synchronizing these fields. No existing employee or payroll row is
-- rewritten by this migration; missing values remain unknown.
ALTER TABLE briskers.employees
  ADD COLUMN IF NOT EXISTS nickname text,
  ADD COLUMN IF NOT EXISTS default_payment_method text;

-- The old detail endpoint remains usable by settings managers, but the tax
-- identifier fragment is only disclosed to an active shop Owner.
CREATE OR REPLACE FUNCTION public.briskers_employee_settings_detail(
  p_business_id uuid, p_employee_id uuid
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $function$
DECLARE v jsonb;
BEGIN
  PERFORM briskers.require_permission(p_business_id,'settings.manage');
  SELECT jsonb_build_object(
    'id',e.id,'name',e.display_name,'phone',coalesce(e.phone,''),
    'email',coalesce(e.email,''),'address',coalesce(e.address,''),
    'position_id',e.position_id,'position',ep.name,
    'compensation_enabled',e.compensation_enabled,
    'payment_type',CASE WHEN e.compensation_enabled THEN coalesce(ec.payment_type,e.payment_type) ELSE NULL END,
    'hourly_rate',CASE WHEN e.compensation_enabled THEN ec.hourly_rate ELSE NULL END,
    'weekly_rate',CASE WHEN e.compensation_enabled THEN ec.weekly_rate ELSE NULL END,
    'active',e.active,'user_linked',e.user_id IS NOT NULL,
    'ssn_last4',CASE WHEN EXISTS (
      SELECT 1 FROM briskers.memberships m WHERE m.business_id=p_business_id
      AND m.user_id=auth.uid() AND m.active AND m.role_code='owner'
    ) THEN priv.ssn_last4 ELSE NULL END
  ) INTO v
  FROM briskers.employees e
  LEFT JOIN briskers.employee_positions ep ON ep.business_id=e.business_id AND ep.id=e.position_id
  LEFT JOIN LATERAL (
    SELECT c.payment_type,c.hourly_rate,c.weekly_rate FROM briskers.employee_compensation c
    WHERE c.business_id=e.business_id AND c.employee_id=e.id AND c.effective_from<=current_date
    ORDER BY c.effective_from DESC LIMIT 1
  ) ec ON TRUE
  LEFT JOIN briskers.employee_private priv ON priv.business_id=e.business_id AND priv.employee_id=e.id
  WHERE e.business_id=p_business_id AND e.id=p_employee_id;
  IF v IS NULL THEN RAISE EXCEPTION 'Employee not found' USING ERRCODE='P0002'; END IF;
  RETURN v;
END
$function$;

CREATE OR REPLACE FUNCTION public.briskers_employee_profile_metadata_v1(
  p_business_id uuid,p_employee_id uuid
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $function$
DECLARE v jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS (
    SELECT 1 FROM briskers.memberships m WHERE m.business_id=p_business_id
    AND m.user_id=auth.uid() AND m.active AND m.role_code='owner'
  ) THEN RAISE EXCEPTION 'Owner access required' USING ERRCODE='42501'; END IF;
  PERFORM briskers.require_permission(p_business_id,'settings.manage');
  SELECT jsonb_build_object('id',e.id,'nickname',coalesce(e.nickname,''),
    'default_payment_method',e.default_payment_method) INTO v
  FROM briskers.employees e WHERE e.business_id=p_business_id AND e.id=p_employee_id;
  IF v IS NULL THEN RAISE EXCEPTION 'Employee not found' USING ERRCODE='P0002'; END IF;
  RETURN v;
END
$function$;

CREATE OR REPLACE FUNCTION public.briskers_patch_employee_profile_metadata_v1(
  p_business_id uuid,p_employee_id uuid,p_base jsonb,p_patch jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $function$
DECLARE current_detail jsonb; k text; conflicts jsonb:='[]'::jsonb; changed boolean:=false;
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS (
    SELECT 1 FROM briskers.memberships m WHERE m.business_id=p_business_id
    AND m.user_id=auth.uid() AND m.active AND m.role_code='owner'
  ) THEN RAISE EXCEPTION 'Owner access required' USING ERRCODE='42501'; END IF;
  PERFORM briskers.require_permission(p_business_id,'settings.manage');
  IF jsonb_typeof(p_base) IS DISTINCT FROM 'object' OR
     jsonb_typeof(p_patch) IS DISTINCT FROM 'object' OR p_patch='{}'::jsonb THEN
    RAISE EXCEPTION 'Explicit non-empty patch and baseline required' USING ERRCODE='22023';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_object_keys(p_patch) f WHERE f NOT IN
    ('nickname','default_payment_method')) THEN
    RAISE EXCEPTION 'Unsupported employee field' USING ERRCODE='22023';
  END IF;
  IF p_patch ? 'nickname' AND (
    jsonb_typeof(p_patch->'nickname') IS DISTINCT FROM 'string' OR
    length(btrim(p_patch->>'nickname'))>32 OR
    p_patch->>'nickname' ~ '[\r\n]') THEN
    RAISE EXCEPTION 'Invalid nickname' USING ERRCODE='22023';
  END IF;
  IF p_patch ? 'default_payment_method' AND
     jsonb_typeof(p_patch->'default_payment_method') NOT IN ('null','string') THEN
    RAISE EXCEPTION 'Invalid payment method' USING ERRCODE='22023';
  END IF;
  IF p_patch ? 'default_payment_method' AND
     p_patch->>'default_payment_method' IS NOT NULL AND
     p_patch->>'default_payment_method' NOT IN ('Cash','Zelle','Check','ACH','Card','Other') THEN
    RAISE EXCEPTION 'Invalid payment method' USING ERRCODE='22023';
  END IF;
  PERFORM 1 FROM briskers.employees WHERE business_id=p_business_id AND id=p_employee_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Employee not found' USING ERRCODE='P0002'; END IF;
  current_detail:=public.briskers_employee_profile_metadata_v1(p_business_id,p_employee_id);
  FOR k IN SELECT jsonb_object_keys(p_patch) LOOP
    IF NOT (p_base ? k) THEN conflicts:=conflicts||jsonb_build_array(k);
    ELSIF current_detail->k IS NOT DISTINCT FROM p_patch->k THEN CONTINUE;
    ELSIF current_detail->k IS DISTINCT FROM p_base->k THEN conflicts:=conflicts||jsonb_build_array(k);
    ELSE changed:=true;
    END IF;
  END LOOP;
  IF conflicts<>'[]'::jsonb THEN RETURN jsonb_build_object('conflict',true,'fields',conflicts); END IF;
  IF changed THEN
    UPDATE briskers.employees e SET
      nickname=CASE WHEN p_patch ? 'nickname' THEN nullif(btrim(p_patch->>'nickname'),'') ELSE e.nickname END,
      default_payment_method=CASE WHEN p_patch ? 'default_payment_method'
        THEN p_patch->>'default_payment_method' ELSE e.default_payment_method END,
      updated_at=clock_timestamp(),row_version=e.row_version+1
    WHERE e.business_id=p_business_id AND e.id=p_employee_id;
  END IF;
  RETURN jsonb_build_object('conflict',false,'details',
    public.briskers_employee_profile_metadata_v1(p_business_id,p_employee_id));
END
$function$;

REVOKE ALL ON FUNCTION public.briskers_employee_profile_metadata_v1(uuid,uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.briskers_patch_employee_profile_metadata_v1(uuid,uuid,jsonb,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.briskers_employee_profile_metadata_v1(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.briskers_patch_employee_profile_metadata_v1(uuid,uuid,jsonb,jsonb) TO authenticated;
