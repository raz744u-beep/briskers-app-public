-- Owner-only deletion of an unused, unreferenced native Job.
-- Avoid all service history loss; existing references prevent deletion through
-- explicit guards and remaining foreign keys. Return its number only after
-- successful deletion inside the same transaction.
CREATE OR REPLACE FUNCTION public.briskers_delete_unused_job(
  p_business_id uuid, p_job_id uuid
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  j briskers.jobs;
  pfx text;
  num_part text;
BEGIN
  IF NOT briskers.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Owner access required' USING ERRCODE='42501';
  END IF;
  SELECT * INTO j FROM briskers.jobs
  WHERE business_id=p_business_id AND id=p_job_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Job not found' USING ERRCODE='P0002';
  END IF;
  IF EXISTS(SELECT 1 FROM briskers.sales_documents d
            WHERE d.business_id=p_business_id AND d.job_id=p_job_id)
     OR EXISTS(SELECT 1 FROM briskers.job_pre_inspections i
            WHERE i.business_id=p_business_id AND i.job_id=p_job_id)
     OR (SELECT count(*) FROM briskers.job_visits v
         WHERE v.business_id=p_business_id AND v.job_id=p_job_id)>1
     OR EXISTS(SELECT 1 FROM briskers.job_visits v
            WHERE v.business_id=p_business_id AND v.job_id=p_job_id
              AND (v.visit_number<>1 OR v.work_summary IS NOT NULL
                   OR v.closed_at IS NOT NULL OR v.planned_hours<>0))
     OR EXISTS(SELECT 1 FROM briskers.job_status_events e
            WHERE e.business_id=p_business_id AND e.job_id=p_job_id
              AND (e.from_status IS NOT NULL OR e.to_status<>'open'
                   OR e.note IS DISTINCT FROM 'Job created'))
  THEN
    RAISE EXCEPTION 'This Job has related work or history and cannot be deleted'
      USING ERRCODE='55000';
  END IF;
  -- Restricting foreign keys will reject additional dependencies, including
  -- expenses, assignments, appointments, attachments and notes.
  DELETE FROM briskers.job_visits
    WHERE business_id=p_business_id AND job_id=p_job_id;
  DELETE FROM briskers.job_status_events
    WHERE business_id=p_business_id AND job_id=p_job_id;
  DELETE FROM briskers.jobs
    WHERE business_id=p_business_id AND id=p_job_id;
  SELECT prefix INTO pfx FROM briskers.document_counters
    WHERE business_id=p_business_id AND document_kind='job';
  IF coalesce(pfx,'')='' THEN
    num_part := j.job_number;
  ELSIF left(j.job_number,length(pfx))=pfx THEN
    num_part := substring(j.job_number from length(pfx)+1);
  END IF;
  IF num_part ~ '^[0-9]+$' THEN
    INSERT INTO briskers.document_number_reuse(
      business_id,document_kind,number_value,prefix
    ) VALUES(p_business_id,'job',num_part::bigint,coalesce(pfx,''))
    ON CONFLICT DO NOTHING;
  END IF;
  RETURN true;
END
$function$;

REVOKE ALL ON FUNCTION public.briskers_delete_unused_job(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.briskers_delete_unused_job(uuid,uuid) TO authenticated;
