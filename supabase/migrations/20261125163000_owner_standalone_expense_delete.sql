-- Keep identity only. This works for server IDs and for creates whose reply
-- was lost, without retaining a second copy of the expense.
CREATE TABLE IF NOT EXISTS briskers.standalone_expense_deletions_v1 (
  deletion_seq bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  business_id uuid NOT NULL,
  transaction_id uuid,
  create_operation text,
  CHECK (transaction_id IS NOT NULL OR create_operation IS NOT NULL),
  UNIQUE (business_id, transaction_id),
  UNIQUE (business_id, create_operation)
);
REVOKE ALL ON briskers.standalone_expense_deletions_v1 FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION briskers.reject_deleted_standalone_expense_create_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $body$
BEGIN
  IF NEW.entity_type = 'financial_transaction_create'
     AND left(NEW.operation_id, 17) = 'financial-create-'
     AND EXISTS (
       SELECT 1 FROM briskers.standalone_expense_deletions_v1 d
       WHERE d.business_id=NEW.business_id AND d.create_operation=NEW.operation_id
     ) THEN
    RAISE EXCEPTION 'Expense creation was canceled by the Owner' USING ERRCODE='PT409';
  END IF;
  RETURN NEW;
END
$body$;
REVOKE ALL ON FUNCTION briskers.reject_deleted_standalone_expense_create_v1() FROM PUBLIC;
DROP TRIGGER IF EXISTS briskers_reject_deleted_standalone_expense_create_v1
  ON briskers.sync_applied_operations;
CREATE TRIGGER briskers_reject_deleted_standalone_expense_create_v1
  BEFORE INSERT ON briskers.sync_applied_operations
  FOR EACH ROW EXECUTE FUNCTION briskers.reject_deleted_standalone_expense_create_v1();

CREATE OR REPLACE FUNCTION public.briskers_delete_standalone_expense_v1(
  p_business_id uuid, p_transaction_id uuid, p_create_operation text,
  p_preserve_ids uuid[] DEFAULT '{}'::uuid[]
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $body$
DECLARE
  target uuid := p_transaction_id;
  original briskers.financial_transactions%ROWTYPE;
  fields jsonb;
BEGIN
  IF auth.uid() IS NULL OR briskers.is_owner(p_business_id) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Owner access required' USING ERRCODE='42501';
  END IF;
  IF (p_transaction_id IS NULL) = (p_create_operation IS NULL)
     OR (p_create_operation IS NOT NULL
         AND p_create_operation !~ '^financial-create-[A-Za-z0-9-]{1,90}$') THEN
    RAISE EXCEPTION 'A financial transaction or its create identity is required'
      USING ERRCODE='22023';
  END IF;
  -- Serialize feed entries per business and use the same create-operation lock
  -- as briskers_sync_create_manual_transaction_v1 (November 16 migration).
  PERFORM pg_advisory_xact_lock(hashtextextended('briskers:financial-deletes:' || p_business_id::text,0));
  IF p_create_operation IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtextextended(
      'briskers:financial-operation:' || p_business_id::text || ':' || p_create_operation,0));
    SELECT (o.result->>'transaction_id')::uuid INTO target
    FROM briskers.sync_applied_operations o
    WHERE o.business_id=p_business_id AND o.operation_id=p_create_operation
      AND o.entity_type='financial_transaction_create';
  END IF;
  IF target = ANY(coalesce(p_preserve_ids,'{}'::uuid[])) THEN
    RETURN NULL;
  END IF;

  IF target IS NOT NULL THEN
    SELECT t.* INTO original FROM briskers.financial_transactions t
    WHERE t.business_id=p_business_id AND t.id=target FOR UPDATE;
    IF FOUND THEN
      fields := to_jsonb(original);
      IF coalesce(original.kind::text,'') NOT IN ('supplier_expense','other_expense')
        OR EXISTS (
          SELECT 1 FROM jsonb_each_text(fields) f
          WHERE f.key IN ('recurring_rule_id','transfer_group_id','invoice_payment_id',
                          'payment_id','document_id','invoice_id','job_id')
            AND f.value IS NOT NULL
        ) OR EXISTS (
          SELECT 1 FROM briskers.payment_allocations a
          WHERE a.business_id=p_business_id AND a.transaction_id=target
        ) OR EXISTS (
          SELECT 1 FROM briskers.sync_applied_operations o
          WHERE o.business_id=p_business_id AND o.entity_type='financial_transaction_create'
            AND left(o.operation_id,18)='payroll-financial-'
            AND o.result->>'transaction_id'=target::text
        ) THEN
        RAISE EXCEPTION 'This expense belongs to a linked transaction' USING ERRCODE='PT409';
      END IF;
      DELETE FROM briskers.financial_transactions t
      WHERE t.business_id=p_business_id AND t.id=target;
    END IF;
  END IF;
  IF target IS NOT NULL OR p_create_operation IS NOT NULL THEN
    INSERT INTO briskers.standalone_expense_deletions_v1
      (business_id,transaction_id,create_operation)
    VALUES (p_business_id,target,p_create_operation)
    ON CONFLICT DO NOTHING;
  END IF;
  RETURN target;
END
$body$;

CREATE OR REPLACE FUNCTION public.briskers_expense_deletion_feed_v1(
  p_business_id uuid, p_after bigint
) RETURNS TABLE(deletion_seq bigint, transaction_id uuid)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $body$
BEGIN
  IF auth.uid() IS NULL OR briskers.is_owner(p_business_id) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Owner access required' USING ERRCODE='42501';
  END IF;
  RETURN QUERY SELECT d.deletion_seq,d.transaction_id
  FROM briskers.standalone_expense_deletions_v1 d
  WHERE d.business_id=p_business_id AND d.deletion_seq>coalesce(p_after,0)
    AND d.transaction_id IS NOT NULL
  ORDER BY d.deletion_seq LIMIT 100;
END
$body$;

REVOKE ALL ON FUNCTION public.briskers_delete_standalone_expense_v1(uuid,uuid,text,uuid[]) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.briskers_expense_deletion_feed_v1(uuid,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.briskers_delete_standalone_expense_v1(uuid,uuid,text,uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.briskers_expense_deletion_feed_v1(uuid,bigint) TO authenticated;
