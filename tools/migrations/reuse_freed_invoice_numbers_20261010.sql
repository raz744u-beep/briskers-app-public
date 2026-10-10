-- Restore reuse of eligible deleted invoice numbers; estimates/jobs already
-- have the same behavior. Retain advisory lock and live collision checks.
-- Only the allocator is changed; no existing numbers, documents, or pool rows
-- are modified by this migration.
CREATE OR REPLACE FUNCTION briskers.next_number(b uuid,k text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE n bigint; p text; taken boolean; attempts integer:=0;
BEGIN
  IF k NOT IN ('invoice','estimate','job','credit_note') THEN
    RAISE EXCEPTION 'Unsupported document number kind: %',k
      USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext(b::text||':'||k));
  LOOP
    attempts:=attempts+1;
    IF attempts>100000 THEN
      RAISE EXCEPTION 'Could not find an available document number for %',k;
    END IF;
    n:=NULL; p:=NULL;
    IF k IN ('invoice','estimate','job','credit_note') THEN
      SELECT r.number_value,r.prefix INTO n,p
      FROM briskers.document_number_reuse r
      WHERE r.business_id=b AND r.document_kind=k
      ORDER BY r.number_value
      LIMIT 1 FOR UPDATE SKIP LOCKED;
      IF FOUND THEN
        DELETE FROM briskers.document_number_reuse
        WHERE business_id=b AND document_kind=k AND number_value=n;
      END IF;
    END IF;
    IF n IS NULL THEN
      UPDATE briskers.document_counters
      SET next_number=next_number+1,updated_at=clock_timestamp()
      WHERE business_id=b AND document_kind=k
      RETURNING next_number-1,prefix INTO n,p;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Document counter not initialized: %',k
          USING ERRCODE='55000';
      END IF;
    END IF;
    IF k='job' THEN
      SELECT EXISTS(SELECT 1 FROM briskers.jobs j
        WHERE j.business_id=b AND j.job_number=coalesce(p,'')||n::text)
      INTO taken;
    ELSE
      SELECT EXISTS(SELECT 1 FROM briskers.sales_documents d
        WHERE d.business_id=b AND d.kind=k
          AND d.document_number=coalesce(p,'')||n::text)
      INTO taken;
    END IF;
    IF NOT taken THEN
      RETURN coalesce(p,'')||n::text;
    END IF;
  END LOOP;
END $function$;
