-- JOB-005: First actual Work Performed save on imported jobs with no visits.
-- Only a new explicit save may create a visit; preserves findings and legacy dates.
CREATE OR REPLACE FUNCTION public.briskers_create_missing_work_visit_v1(
 p_business_id uuid,p_job_id uuid,p_operation_id text,p_work_summary text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE v briskers.job_visits; result jsonb;
BEGIN
 IF nullif(btrim(coalesce(p_operation_id,'')),'') IS NULL OR length(p_operation_id)>160 THEN
   RAISE EXCEPTION 'Missing work-save operation identity' USING ERRCODE='22023';
 END IF;
 IF nullif(btrim(coalesce(p_work_summary,'')),'') IS NULL THEN
   RAISE EXCEPTION 'Work Performed entry required' USING ERRCODE='22023';
 END IF;
 IF NOT briskers.can(p_business_id,'jobs.edit')
    AND NOT (briskers.can(p_business_id,'jobs.work.edit_assigned')
      AND briskers.is_assigned(p_business_id,p_job_id)) THEN
   RAISE EXCEPTION 'Job work access denied' USING ERRCODE='42501';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtext(p_business_id::text||':missing-visit:'||p_job_id::text));
 SELECT o.result INTO result FROM briskers.sync_applied_operations o
 WHERE o.business_id=p_business_id AND o.operation_id=p_operation_id;
 IF result IS NOT NULL THEN RETURN result; END IF;
 IF NOT EXISTS(SELECT 1 FROM briskers.jobs j WHERE j.business_id=p_business_id AND j.id=p_job_id) THEN
   RAISE EXCEPTION 'Job not found' USING ERRCODE='P0002';
 END IF;
 IF EXISTS(SELECT 1 FROM briskers.job_visits WHERE business_id=p_business_id AND job_id=p_job_id) THEN
   RAISE EXCEPTION 'Job already has visits; use normal version-checked save' USING ERRCODE='23505';
 END IF;
 INSERT INTO briskers.job_visits(business_id,job_id,visit_number,work_summary,opened_at,created_by)
 VALUES(p_business_id,p_job_id,1,btrim(p_work_summary),clock_timestamp(),auth.uid())
 RETURNING * INTO v;
 result:=jsonb_build_object('status','applied','visit',jsonb_build_object(
  'id',v.id,'job_id',v.job_id,'visit_number',v.visit_number,'reason',v.reason,
  'planned_hours',v.planned_hours,'work_summary',v.work_summary,
  'opened_at',v.opened_at,'closed_at',v.closed_at,'updated_at',v.updated_at,
  'row_version',v.row_version));
 INSERT INTO briskers.sync_applied_operations(business_id,operation_id,entity_type,result)
 VALUES(p_business_id,p_operation_id,'work_summary_create_visit',result);
 RETURN result;
END $fn$;
REVOKE ALL ON FUNCTION public.briskers_create_missing_work_visit_v1(uuid,uuid,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.briskers_create_missing_work_visit_v1(uuid,uuid,text,text) TO authenticated;
