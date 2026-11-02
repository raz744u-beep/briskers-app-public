-- REVIEW ONLY: no live migration or app data changes.
-- Owner-specific proof that the known disposable mock appointment does not
-- exist on the server. This function does NOT delete any server record.
-- Its answer is a prerequisite for retiring the corresponding local
-- pending_delete tombstone and its exact outbox row.
CREATE OR REPLACE FUNCTION public.briskers_confirm_orphan_mock_absent_v1(
  p_business_id uuid, p_appointment_id uuid
) RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER SET search_path = ''
AS $fn$
BEGIN
  IF NOT briskers.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Owner access required' USING ERRCODE='42501';
  END IF;
  IF p_appointment_id IS DISTINCT FROM
     '93356a11-f16a-4939-aaec-db5593273de3'::uuid THEN
    RAISE EXCEPTION 'Only the verified disposable appointment is eligible'
      USING ERRCODE='22023';
  END IF;

  -- An appointment under any shop with this identity is NOT proven absent.
  -- No customer/job/vehicle/document records are deleted or altered.
  RETURN NOT EXISTS (
    SELECT 1 FROM briskers.appointments a
    WHERE a.id=p_appointment_id
  );
END;
$fn$;
REVOKE ALL ON FUNCTION public.briskers_confirm_orphan_mock_absent_v1(uuid,uuid)
FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.briskers_confirm_orphan_mock_absent_v1(uuid,uuid)
TO authenticated;
