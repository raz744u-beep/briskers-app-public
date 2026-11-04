-- Proposed additive server patch; apply after offline_recurring_recovery.sql.
-- Not deployed by this PR. Every bundle is atomic and serialized with the
-- existing scheduler's rule-row lock. No client-controlled SQL identifiers.
BEGIN;
CREATE TABLE IF NOT EXISTS briskers.recurring_sync_receipts_v1 (
  business_id uuid NOT NULL,
  actor_id uuid NOT NULL,
  operation_id text NOT NULL CHECK (length(operation_id) BETWEEN 1 AND 4000),
  request jsonb NOT NULL,
  response jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(business_id,actor_id,operation_id)
);
ALTER TABLE briskers.recurring_sync_receipts_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON briskers.recurring_sync_receipts_v1 FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.briskers_sync_recurring_bundle_v1(
  p_business_id uuid, p_operation_id text, p_rule jsonb, p_occurrences jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
#variable_conflict use_variable
DECLARE
  r briskers.recurring_transactions%ROWTYPE;
  t briskers.financial_transactions%ROWTYPE;
  item jsonb; result jsonb; request jsonb;
  rule_id uuid; account_id uuid; category_id uuid; vendor_id uuid;
  wanted_amount numeric; same_rule boolean; same_occurrence boolean;
  curr text; normal_direction text; tx_kind text; signed_amount numeric;
  due date; tx_id uuid; output_rows jsonb := '[]'::jsonb;
  prior_request jsonb; prior_response jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501'; END IF;
  PERFORM briskers.require_permission(p_business_id,'settings.manage');
  IF p_operation_id IS NULL OR length(p_operation_id) NOT BETWEEN 1 AND 4000 OR
     jsonb_typeof(p_rule) IS DISTINCT FROM 'object' OR
     jsonb_typeof(p_occurrences) IS DISTINCT FROM 'array' OR
     jsonb_array_length(p_occurrences)>1000 THEN
    RAISE EXCEPTION 'Invalid recurring bundle' USING ERRCODE='22023';
  END IF;
  request := jsonb_build_object('rule',p_rule,'occurrences',p_occurrences);
  -- Advisory lock also serializes creation of a previously local rule. Existing
  -- rules additionally use the row lock shared by the production scheduler.
  rule_id := (p_rule->>'id')::uuid;
  IF rule_id IS NULL OR (p_rule->>'business_id')::uuid IS DISTINCT FROM p_business_id THEN
    RAISE EXCEPTION 'Rule business mismatch' USING ERRCODE='22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_business_id::text || ':' || rule_id::text,0));
  SELECT s.request,s.response INTO prior_request,prior_response
    FROM briskers.recurring_sync_receipts_v1 s WHERE s.business_id=p_business_id
      AND s.actor_id=auth.uid() AND s.operation_id=p_operation_id;
  IF FOUND THEN
    IF prior_request IS DISTINCT FROM request THEN
      RAISE EXCEPTION 'Operation ID reused with different data' USING ERRCODE='22023';
    END IF;
    RETURN prior_response;
  END IF;
  account_id := (p_rule->>'account_id')::uuid;
  category_id := (p_rule->>'category_id')::uuid;
  vendor_id := nullif(p_rule->>'vendor_id','')::uuid;
  wanted_amount := (p_rule->>'amount_minor')::numeric / 100;
  IF wanted_amount IS NULL OR wanted_amount<=0 OR wanted_amount<>round(wanted_amount,2)
    OR coalesce(p_rule->>'direction','') NOT IN ('expense','income')
    OR coalesce(p_rule->>'frequency','') NOT IN ('daily','weekly','monthly','yearly')
    OR coalesce((p_rule->>'interval_count')::int,0) NOT BETWEEN 1 AND 1000
    OR p_rule->>'next_date' IS NULL OR jsonb_typeof(p_rule->'is_repeating') IS DISTINCT FROM 'boolean' THEN
    RAISE EXCEPTION 'Invalid recurring schedule' USING ERRCODE='22023';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM briskers.financial_accounts a WHERE a.business_id=p_business_id AND a.id=account_id AND a.active)
    OR NOT EXISTS(SELECT 1 FROM briskers.financial_categories c WHERE c.business_id=p_business_id AND c.id=category_id AND c.active)
    OR (vendor_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM briskers.vendors v WHERE v.business_id=p_business_id AND v.id=vendor_id AND v.active)) THEN
    RAISE EXCEPTION 'Recurring reference is unavailable' USING ERRCODE='22023';
  END IF;
  SELECT * INTO r FROM briskers.recurring_transactions
    WHERE business_id=p_business_id AND id=rule_id FOR UPDATE;
  IF NOT FOUND THEN
    IF p_rule->>'row_version' IS NOT NULL THEN
      RAISE EXCEPTION 'Schedule was removed' USING ERRCODE='40001';
    END IF;
    INSERT INTO briskers.recurring_transactions(id,business_id,direction,vendor_id,
      account_id,category_id,amount,remarks,frequency,interval_count,next_date,
      end_date,is_repeating,created_by)
    VALUES(rule_id,p_business_id,p_rule->>'direction',vendor_id,account_id,category_id,
      wanted_amount,nullif(p_rule->>'remarks',''),p_rule->>'frequency',
      (p_rule->>'interval_count')::int,(p_rule->>'next_date')::date,
      (p_rule->>'end_date')::date,(p_rule->>'is_repeating')::boolean,auth.uid());
  ELSE
    same_rule := r.direction=p_rule->>'direction' AND r.account_id=account_id
      AND r.category_id=category_id AND r.vendor_id IS NOT DISTINCT FROM vendor_id
      AND r.amount=wanted_amount AND coalesce(r.remarks,'')=coalesce(p_rule->>'remarks','')
      AND r.frequency=p_rule->>'frequency' AND r.interval_count=(p_rule->>'interval_count')::int
      AND r.next_date=(p_rule->>'next_date')::date
      AND r.end_date IS NOT DISTINCT FROM (p_rule->>'end_date')::date
      AND r.is_repeating=(p_rule->>'is_repeating')::boolean;
    IF NOT same_rule THEN
      IF r.row_version IS DISTINCT FROM (p_rule->>'row_version')::bigint THEN
        RAISE EXCEPTION 'Schedule changed on the server' USING ERRCODE='40001';
      END IF;
      UPDATE briskers.recurring_transactions SET direction=p_rule->>'direction',
        vendor_id=vendor_id,account_id=account_id,category_id=category_id,
        amount=wanted_amount,remarks=nullif(p_rule->>'remarks',''),
        frequency=p_rule->>'frequency',interval_count=(p_rule->>'interval_count')::int,
        next_date=(p_rule->>'next_date')::date,end_date=(p_rule->>'end_date')::date,
        is_repeating=(p_rule->>'is_repeating')::boolean
      WHERE business_id=p_business_id AND id=rule_id;
    END IF;
  END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_occurrences) e
    GROUP BY e->>'recurring_occurrence_date' HAVING count(*)>1) THEN
    RAISE EXCEPTION 'Duplicate occurrence in bundle' USING ERRCODE='22023';
  END IF;
  FOR item IN SELECT value FROM jsonb_array_elements(p_occurrences) LOOP
    IF (item->>'business_id')::uuid IS DISTINCT FROM p_business_id OR
       (item->>'recurring_rule_id')::uuid IS DISTINCT FROM rule_id THEN
      RAISE EXCEPTION 'Occurrence scope mismatch' USING ERRCODE='22023';
    END IF;
    due := (item->>'recurring_occurrence_date')::date;
    wanted_amount := (item->>'amount_minor')::numeric/100;
    IF due IS NULL OR wanted_amount IS NULL OR wanted_amount<=0 OR
      wanted_amount<>round(wanted_amount,2) OR item->>'date' IS NULL OR
      coalesce(item->>'direction','') NOT IN ('expense','income') THEN
      RAISE EXCEPTION 'Invalid occurrence' USING ERRCODE='22023';
    END IF;
    SELECT * INTO t FROM briskers.financial_transactions
      WHERE business_id=p_business_id AND recurring_rule_id=rule_id
        AND recurring_occurrence_date=due FOR UPDATE;
    IF FOUND THEN
      same_occurrence := abs(t.amount)=wanted_amount AND
        (CASE WHEN t.amount<0 THEN 'expense' ELSE 'income' END)=item->>'direction'
        AND t.account_id=(item->>'account_id')::uuid AND t.category_id=(item->>'category_id')::uuid
        AND t.vendor_id IS NOT DISTINCT FROM (item->>'vendor_id')::uuid
        AND t.transaction_date=(item->>'date')::date
        AND coalesce(t.remarks,'')=coalesce(item->>'remarks','');
      IF t.status<>'posted' THEN RAISE EXCEPTION 'Occurrence is not posted' USING ERRCODE='40001'; END IF;
      IF NOT same_occurrence THEN
        -- Current engine edits amounts only. Never rewrite a split allocation,
        -- account, date or payee through this restricted correction endpoint.
        IF t.row_version IS DISTINCT FROM (item->>'row_version')::bigint OR
          t.account_id IS DISTINCT FROM (item->>'account_id')::uuid OR
          t.category_id IS DISTINCT FROM (item->>'category_id')::uuid OR
          t.vendor_id IS DISTINCT FROM (item->>'vendor_id')::uuid OR
          t.transaction_date IS DISTINCT FROM (item->>'date')::date OR
          (CASE WHEN t.amount<0 THEN 'expense' ELSE 'income' END)<>item->>'direction' OR
          coalesce(t.remarks,'')<>coalesce(item->>'remarks','') THEN
          RAISE EXCEPTION 'Occurrence changed on the server' USING ERRCODE='40001';
        END IF;
        IF t.kind IN ('supplier_expense','other_expense','supplier_refund') AND
          (SELECT count(*) FROM briskers.expense_allocations a
            WHERE a.business_id=p_business_id AND a.transaction_id=t.id)<>1 THEN
          RAISE EXCEPTION 'Split occurrence requires manual reconciliation' USING ERRCODE='40001';
        END IF;
        signed_amount := CASE WHEN item->>'direction'='expense' THEN -wanted_amount ELSE wanted_amount END;
        UPDATE briskers.financial_transactions SET amount=signed_amount
          WHERE business_id=p_business_id AND id=t.id;
        UPDATE briskers.expense_allocations SET amount=-signed_amount
          WHERE business_id=p_business_id AND transaction_id=t.id;
      END IF;
      tx_id := t.id;
    ELSE
      IF item->>'row_version' IS NOT NULL THEN
        RAISE EXCEPTION 'Occurrence was removed' USING ERRCODE='40001';
      END IF;
      SELECT a.currency_code INTO curr FROM briskers.financial_accounts a
        WHERE a.business_id=p_business_id AND a.id=(item->>'account_id')::uuid AND a.active;
      SELECT c.normal_direction INTO normal_direction FROM briskers.financial_categories c
        WHERE c.business_id=p_business_id AND c.id=(item->>'category_id')::uuid AND c.active;
      IF curr IS NULL OR normal_direction IS NULL OR
        ((item->>'vendor_id') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM briskers.vendors v
          WHERE v.business_id=p_business_id AND v.id=(item->>'vendor_id')::uuid AND v.active)) THEN
        RAISE EXCEPTION 'Occurrence reference is unavailable' USING ERRCODE='22023';
      END IF;
      tx_kind := CASE WHEN item->>'direction'='expense' AND normal_direction='income' THEN 'other_expense'
        WHEN item->>'direction'='expense' THEN 'supplier_expense'
        WHEN normal_direction='expense' THEN 'supplier_refund' ELSE 'other_income' END;
      signed_amount := CASE WHEN item->>'direction'='expense' THEN -wanted_amount ELSE wanted_amount END;
      INSERT INTO briskers.financial_transactions(business_id,account_id,category_id,kind,
        amount,currency_code,transaction_date,vendor_id,remarks,idempotency_key,
        recurring_rule_id,recurring_occurrence_date,created_by)
      VALUES(p_business_id,(item->>'account_id')::uuid,(item->>'category_id')::uuid,
        tx_kind,signed_amount,curr,(item->>'date')::date,(item->>'vendor_id')::uuid,
        nullif(item->>'remarks',''),gen_random_uuid(),rule_id,due,auth.uid()) RETURNING id INTO tx_id;
      IF tx_kind IN ('supplier_expense','other_expense','supplier_refund') THEN
        INSERT INTO briskers.expense_allocations(business_id,transaction_id,category_id,amount,created_by)
          VALUES(p_business_id,tx_id,(item->>'category_id')::uuid,-signed_amount,auth.uid());
      END IF;
    END IF;
    SELECT * INTO t FROM briskers.financial_transactions WHERE business_id=p_business_id AND id=tx_id;
    output_rows := output_rows || jsonb_build_array(to_jsonb(t) || jsonb_build_object(
      'amount_minor',(abs(t.amount)*100)::bigint,'date',t.transaction_date,
      'direction',CASE WHEN t.amount<0 THEN 'expense' ELSE 'income' END));
  END LOOP;
  SELECT * INTO r FROM briskers.recurring_transactions WHERE business_id=p_business_id AND id=rule_id;
  result := jsonb_build_object('business_id',p_business_id,
    'rule',to_jsonb(r)||jsonb_build_object('amount_minor',(r.amount*100)::bigint),
    'occurrences',output_rows);
  INSERT INTO briskers.recurring_sync_receipts_v1(business_id,actor_id,operation_id,request,response)
    VALUES(p_business_id,auth.uid(),p_operation_id,request,result);
  RETURN result;
END;
$$;
REVOKE ALL ON FUNCTION public.briskers_sync_recurring_bundle_v1(uuid,text,jsonb,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.briskers_sync_recurring_bundle_v1(uuid,text,jsonb,jsonb) TO authenticated;
COMMIT;
