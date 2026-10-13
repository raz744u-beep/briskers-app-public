-- Owner-only bounded discovery for guarded test-job cleanup preview.
-- Avoid loading the full imported Jobs table during entry to the cleanup page.
CREATE OR REPLACE FUNCTION public.briskers_test_job_cleanup_candidates_v1(p_business_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT briskers.is_owner(p_business_id) THEN
   RAISE EXCEPTION 'Owner access required' USING ERRCODE='42501';
 END IF;
 RETURN COALESCE((
   SELECT jsonb_agg(jsonb_build_object('id',x.id,'job_number',x.job_number,
       'title',x.title,'customer_name',x.customer_name) ORDER BY x.created_at DESC)
   FROM (
     SELECT j.id,j.job_number,j.title,j.created_at,c.display_name AS customer_name
     FROM briskers.jobs j
     LEFT JOIN briskers.customers c ON c.business_id=j.business_id AND c.id=j.customer_id
     WHERE j.business_id=p_business_id
     ORDER BY j.created_at DESC NULLS LAST LIMIT 150
   ) x
 ), '[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.briskers_test_job_cleanup_candidates_v1(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.briskers_test_job_cleanup_candidates_v1(uuid) TO authenticated;
