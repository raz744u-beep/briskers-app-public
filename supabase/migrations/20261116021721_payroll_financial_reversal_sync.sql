-- Serialize same-key creation before any financial write.
DO $migration$
DECLARE
  definition text := pg_get_functiondef(
    'public.briskers_sync_create_manual_transaction_v1(uuid,text,text,uuid,uuid,numeric,date,uuid,uuid,uuid,text,text)'::regprocedure
  );
  anchor text := '  select o.result into v_result';
BEGIN
  IF strpos(definition, 'briskers:financial-operation:') = 0 THEN
    IF strpos(definition, anchor) = 0 THEN
      RAISE EXCEPTION 'Expected financial sync definition is missing';
    END IF;
    EXECUTE replace(definition, anchor,
      E'  perform pg_advisory_xact_lock(hashtextextended(\'briskers:financial-operation:\'||p_business_id::text||\':\'||p_operation_id,0));\n' || anchor);
  END IF;
END
$migration$;

CREATE OR REPLACE FUNCTION public.briskers_sync_payroll_expense_reversal_v1(
  p_business_id uuid, p_payroll_operation text, p_transaction_id uuid,
  p_expected_amount numeric, p_verified_date date
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $body$
DECLARE
  create_key text;
  original briskers.financial_transactions%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR briskers.is_owner(p_business_id) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Owner access required' USING ERRCODE = '42501';
  END IF;
  IF p_payroll_operation IS NULL OR length(p_payroll_operation) NOT BETWEEN 1 AND 90
      OR p_expected_amount IS NULL OR p_expected_amount <= 0 OR p_verified_date IS NULL THEN
    RAISE EXCEPTION 'Invalid payroll expense proof' USING ERRCODE = '22023';
  END IF;
  create_key := format('payroll-financial-payroll-expense-%s:%s-%s:%s',
    length(p_business_id::text), p_business_id, length(p_payroll_operation), p_payroll_operation);
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'briskers:financial-operation:' || p_business_id::text || ':' || create_key, 0));
  SELECT t.* INTO original
  FROM briskers.financial_transactions t
  JOIN briskers.sync_applied_operations o ON o.business_id=t.business_id
    AND o.operation_id=create_key AND o.entity_type='financial_transaction_create'
    AND o.result->>'transaction_id'=t.id::text
  JOIN briskers.financial_categories c ON c.business_id=t.business_id AND c.id=t.category_id
  WHERE t.business_id=p_business_id AND t.id=p_transaction_id
    AND t.amount=-p_expected_amount AND t.transaction_date=p_verified_date
    AND t.kind IN ('supplier_expense','other_expense') AND lower(btrim(c.name))='payroll'
    AND t.recurring_rule_id IS NULL AND t.transfer_group_id IS NULL
  FOR UPDATE OF t;
  IF NOT FOUND OR original.status NOT IN ('posted','void') THEN
    RAISE EXCEPTION 'The linked payroll expense requires reconciliation' USING ERRCODE = 'PT409';
  END IF;
  IF original.status = 'posted' THEN
    UPDATE briskers.financial_transactions
    SET status='void' WHERE business_id=p_business_id AND id=p_transaction_id;
  END IF;
END
$body$;
REVOKE ALL ON FUNCTION public.briskers_sync_payroll_expense_reversal_v1(uuid,text,uuid,numeric,date)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.briskers_sync_payroll_expense_reversal_v1(uuid,text,uuid,numeric,date)
  TO authenticated;
