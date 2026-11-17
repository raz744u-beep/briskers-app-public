CREATE TABLE IF NOT EXISTS briskers.payroll_expense_amount_sync (
  business_id uuid NOT NULL,
  payroll_operation text NOT NULL,
  revision integer NOT NULL,
  transaction_id uuid NOT NULL,
  previous_amount numeric NOT NULL,
  amount numeric NOT NULL,
  verified_date date NOT NULL,
  actor_id uuid NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (business_id, payroll_operation, revision)
);
ALTER TABLE briskers.payroll_expense_amount_sync ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON briskers.payroll_expense_amount_sync FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.briskers_sync_payroll_expense_amount_v1(
  p_business_id uuid, p_payroll_operation text, p_transaction_id uuid,
  p_expected_amount numeric, p_amount numeric, p_verified_date date, p_revision integer
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $body$
DECLARE
  create_key text;
  prior briskers.payroll_expense_amount_sync%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR briskers.is_owner(p_business_id) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Owner access required' USING ERRCODE = '42501';
  END IF;
  IF p_payroll_operation IS NULL OR length(p_payroll_operation) NOT BETWEEN 1 AND 90
      OR p_expected_amount IS NULL OR p_expected_amount NOT BETWEEN 0.01 AND 1000000
      OR p_amount IS NULL OR p_amount NOT BETWEEN 0.01 AND 1000000
      OR p_amount <> round(p_amount, 2) OR p_expected_amount <> round(p_expected_amount, 2)
      OR p_verified_date IS NULL OR p_transaction_id IS NULL
      OR p_revision IS NULL OR p_revision <= 0 THEN
    RAISE EXCEPTION 'Invalid payroll expense correction' USING ERRCODE = '22023';
  END IF;
  create_key := format('payroll-financial-payroll-expense-%s:%s-%s:%s',
    length(p_business_id::text), p_business_id, length(p_payroll_operation), p_payroll_operation);
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'briskers:financial-operation:' || p_business_id::text || ':' || create_key, 0));
  SELECT * INTO prior FROM briskers.payroll_expense_amount_sync
  WHERE business_id=p_business_id AND payroll_operation=p_payroll_operation
    AND revision=p_revision;
  IF FOUND THEN
    IF prior.transaction_id=p_transaction_id AND prior.previous_amount=p_expected_amount
        AND prior.amount=p_amount AND prior.verified_date=p_verified_date THEN
      RETURN;
    END IF;
    RAISE EXCEPTION 'The payroll correction differs from the synchronized revision' USING ERRCODE = 'PT409';
  END IF;
  IF EXISTS (SELECT 1 FROM briskers.payroll_expense_amount_sync
    WHERE business_id=p_business_id AND payroll_operation=p_payroll_operation
      AND revision>p_revision) THEN
    RAISE EXCEPTION 'A later payroll correction already exists' USING ERRCODE = 'PT409';
  END IF;

  UPDATE briskers.financial_transactions t SET amount=-p_amount
  WHERE t.business_id=p_business_id AND t.id=p_transaction_id AND t.status='posted'
    AND t.amount=-p_expected_amount AND t.transaction_date=p_verified_date
    AND t.kind IN ('supplier_expense','other_expense')
    AND t.recurring_rule_id IS NULL AND t.transfer_group_id IS NULL
    AND EXISTS (SELECT 1 FROM briskers.financial_categories c WHERE c.business_id=t.business_id
      AND c.id=t.category_id AND lower(btrim(c.name))='payroll')
    AND EXISTS (SELECT 1 FROM briskers.sync_applied_operations o
      WHERE o.business_id=t.business_id AND o.operation_id=create_key
        AND o.entity_type='financial_transaction_create' AND o.result->>'transaction_id'=t.id::text);
  IF NOT FOUND THEN
    RAISE EXCEPTION 'The linked payroll expense requires reconciliation' USING ERRCODE = 'PT409';
  END IF;
  INSERT INTO briskers.payroll_expense_amount_sync
    (business_id,payroll_operation,revision,transaction_id,previous_amount,amount,verified_date,actor_id)
  VALUES (p_business_id,p_payroll_operation,p_revision,p_transaction_id,
    p_expected_amount,p_amount,p_verified_date,auth.uid());
END
$body$;
REVOKE ALL ON FUNCTION public.briskers_sync_payroll_expense_amount_v1(uuid,text,uuid,numeric,numeric,date,integer)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.briskers_sync_payroll_expense_amount_v1(uuid,text,uuid,numeric,numeric,date,integer)
  TO authenticated;
