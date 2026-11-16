-- Proposed additive server patch. Not deployed by this PR.
-- One read-only database snapshot; never runs the server scheduler or writes.
BEGIN;
CREATE OR REPLACE FUNCTION public.briskers_recurring_recovery_v1(p_business_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
DECLARE rules jsonb; occurrences jsonb; options jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501';
  END IF;
  PERFORM briskers.require_permission(p_business_id,'expenses.recurring.read');
  -- Bound payload size explicitly, never silently truncate recovery.
  IF (SELECT count(*) FROM briskers.recurring_transactions
      WHERE business_id=p_business_id)>2000 OR
     (SELECT count(*) FROM briskers.financial_transactions
      WHERE business_id=p_business_id AND recurring_rule_id IS NOT NULL)>10000 THEN
    RAISE EXCEPTION 'Recurring recovery exceeds snapshot limit; paged recovery required';
  END IF;

  SELECT coalesce(jsonb_agg(to_jsonb(r) || jsonb_build_object(
    'amount_minor',(r.amount*100)::bigint,
    'counterparty',v.name,'account',a.name,'category',c.name,
    'paused_reason',CASE
      WHEN a.id IS NULL OR NOT a.active THEN 'Account is inactive'
      WHEN c.id IS NULL OR NOT c.active THEN 'Category is inactive'
      WHEN r.vendor_id IS NOT NULL AND (v.id IS NULL OR NOT v.active)
        THEN 'Payee/payer is inactive'
      ELSE r.paused_reason END
  ) ORDER BY r.id),'[]'::jsonb) INTO rules
  FROM briskers.recurring_transactions r
  LEFT JOIN briskers.financial_accounts a ON a.business_id=r.business_id AND a.id=r.account_id
  LEFT JOIN briskers.financial_categories c ON c.business_id=r.business_id AND c.id=r.category_id
  LEFT JOIN briskers.vendors v ON v.business_id=r.business_id AND v.id=r.vendor_id
  WHERE r.business_id=p_business_id;

  SELECT coalesce(jsonb_agg(
    public.briskers_transaction_detail(p_business_id,t.id) || jsonb_build_object(
      'id',t.id,'business_id',t.business_id,'row_version',t.row_version,
      'recurring_rule_id',t.recurring_rule_id,
      'recurring_occurrence_date',t.recurring_occurrence_date,
      'date',t.transaction_date,'direction',CASE WHEN t.amount<0 THEN 'expense' ELSE 'income' END,
      'amount_minor',(abs(t.amount)*100)::bigint,
      'account_id',t.account_id,'category_id',t.category_id,'vendor_id',t.vendor_id
    ) ORDER BY t.recurring_occurrence_date,t.id),'[]'::jsonb) INTO occurrences
  FROM briskers.financial_transactions t
  WHERE t.business_id=p_business_id AND t.recurring_rule_id IS NOT NULL
    AND t.recurring_occurrence_date IS NOT NULL AND t.status='posted';

  options := public.briskers_transaction_options(p_business_id);
  RETURN jsonb_build_object('schema_version',1,'complete',true,
    'business_id',p_business_id,'rules',rules,'occurrences',occurrences,'options',options,
    'rule_count',jsonb_array_length(rules),'occurrence_count',jsonb_array_length(occurrences));
END;
$$;
REVOKE ALL ON FUNCTION public.briskers_recurring_recovery_v1(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.briskers_recurring_recovery_v1(uuid) TO authenticated;
COMMIT;
