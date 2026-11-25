CREATE TABLE IF NOT EXISTS briskers.owner_estimate_deletions_v1 (
  deletion_seq bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  business_id uuid NOT NULL,
  estimate_id uuid NOT NULL,
  UNIQUE (business_id,estimate_id)
);
REVOKE ALL ON briskers.owner_estimate_deletions_v1 FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION briskers.reject_deleted_estimate_create_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $body$
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext(NEW.business_id::text||':estimate:'||NEW.id::text));
  IF EXISTS (
    SELECT 1 FROM briskers.owner_estimate_deletions_v1 d
    WHERE d.business_id=NEW.business_id AND d.estimate_id=NEW.id
  ) THEN
    RAISE EXCEPTION 'Estimate creation was canceled by the Owner' USING ERRCODE='PT409';
  END IF;
  RETURN NEW;
END
$body$;
REVOKE ALL ON FUNCTION briskers.reject_deleted_estimate_create_v1() FROM PUBLIC;
DROP TRIGGER IF EXISTS briskers_reject_deleted_estimate_create_v1 ON briskers.sales_documents;
CREATE TRIGGER briskers_reject_deleted_estimate_create_v1
  BEFORE INSERT ON briskers.sales_documents
  FOR EACH ROW WHEN (NEW.kind='estimate')
  EXECUTE FUNCTION briskers.reject_deleted_estimate_create_v1();

CREATE OR REPLACE FUNCTION public.briskers_owner_delete_estimate_v1(
  p_business_id uuid, p_estimate_id uuid
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $body$
DECLARE
  original briskers.sales_documents%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR briskers.is_owner(p_business_id) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Owner access required' USING ERRCODE='42501';
  END IF;
  IF p_estimate_id IS NULL THEN
    RAISE EXCEPTION 'Estimate identity required' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('briskers:estimate-deletes:'||p_business_id::text,0));
  PERFORM pg_advisory_xact_lock(hashtext(p_business_id::text||':estimate:'||p_estimate_id::text));
  SELECT d.* INTO original FROM briskers.sales_documents d
  WHERE d.business_id=p_business_id AND d.id=p_estimate_id FOR UPDATE;
  IF FOUND THEN
    IF original.kind IS DISTINCT FROM 'estimate' OR EXISTS (
      SELECT 1 FROM briskers.sales_documents d
      WHERE d.business_id=p_business_id AND d.source_estimate_id=p_estimate_id
    ) OR EXISTS (
      SELECT 1 FROM briskers.sales_document_estimate_links l
      WHERE l.business_id=p_business_id AND l.estimate_id=p_estimate_id
    ) THEN
      RAISE EXCEPTION 'This estimate belongs to an invoice' USING ERRCODE='PT409';
    END IF;
    IF public.briskers_delete_estimate(p_business_id,p_estimate_id) IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'Estimate deletion was not confirmed' USING ERRCODE='PT409';
    END IF;
  END IF;
  INSERT INTO briskers.owner_estimate_deletions_v1 (business_id,estimate_id)
  VALUES (p_business_id,p_estimate_id) ON CONFLICT DO NOTHING;
END
$body$;

CREATE OR REPLACE FUNCTION public.briskers_estimate_deletion_feed_v1(
  p_business_id uuid, p_after bigint
) RETURNS TABLE(deletion_seq bigint, estimate_id uuid)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $body$
BEGIN
  IF auth.uid() IS NULL OR briskers.is_owner(p_business_id) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Owner access required' USING ERRCODE='42501';
  END IF;
  RETURN QUERY SELECT d.deletion_seq,d.estimate_id
  FROM briskers.owner_estimate_deletions_v1 d
  WHERE d.business_id=p_business_id AND d.deletion_seq>coalesce(p_after,0)
  ORDER BY d.deletion_seq LIMIT 100;
END
$body$;

REVOKE ALL ON FUNCTION public.briskers_owner_delete_estimate_v1(uuid,uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.briskers_estimate_deletion_feed_v1(uuid,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.briskers_owner_delete_estimate_v1(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.briskers_estimate_deletion_feed_v1(uuid,bigint) TO authenticated;
