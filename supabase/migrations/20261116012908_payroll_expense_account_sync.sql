CREATE OR REPLACE FUNCTION public.briskers_sync_payroll_expense_account_v1(
  p_business_id uuid, p_transaction_id uuid, p_expected_account_id uuid, p_account_id uuid
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE
  original briskers.financial_transactions%ROWTYPE;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM briskers.memberships m
    WHERE m.business_id = p_business_id AND m.user_id = auth.uid()
      AND m.active AND m.role_code = 'owner'
  ) THEN
    RAISE EXCEPTION 'Owner access is required to change the payroll account.' USING ERRCODE = '42501';
  END IF;

  SELECT t.* INTO original
  FROM briskers.financial_transactions t
  WHERE t.business_id = p_business_id AND t.id = p_transaction_id
    AND t.status = 'posted' AND t.amount < 0
    AND t.transfer_group_id IS NULL AND t.recurring_rule_id IS NULL
    AND (t.kind = 'payroll' OR EXISTS (
      SELECT 1 FROM briskers.financial_categories c
      WHERE c.business_id = p_business_id AND c.id = t.category_id
        AND lower(btrim(c.name)) = 'payroll'
    ))
  FOR UPDATE OF t;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Original posted payroll expense not found.' USING ERRCODE = 'P0002';
  END IF;

  IF original.account_id = p_account_id THEN
    RETURN;
  END IF;
  IF original.account_id IS DISTINCT FROM p_expected_account_id THEN
    RAISE EXCEPTION 'Payroll expense account changed on another device.' USING ERRCODE = '23514';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM briskers.financial_accounts a
    WHERE a.business_id = p_business_id AND a.id = p_account_id
      AND a.active AND a.currency_code = original.currency_code
  ) THEN
    RAISE EXCEPTION 'The selected active account must use the original currency.' USING ERRCODE = '22023';
  END IF;

  UPDATE briskers.financial_transactions
  SET account_id = p_account_id
  WHERE business_id = p_business_id AND id = p_transaction_id;
END
$function$;

REVOKE ALL ON FUNCTION public.briskers_sync_payroll_expense_account_v1(uuid, uuid, uuid, uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.briskers_sync_payroll_expense_account_v1(uuid, uuid, uuid, uuid)
  TO authenticated;
