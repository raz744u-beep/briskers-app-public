-- Preserve the existing list filters/order while adding occurrence identity.
BEGIN;
CREATE OR REPLACE FUNCTION public.briskers_list_transactions_recurring_v1(
  p_business_id uuid,p_limit integer DEFAULT 50,p_offset integer DEFAULT 0,
  p_start_date date DEFAULT NULL,p_end_date date DEFAULT NULL,p_search text DEFAULT NULL,
  p_direction text DEFAULT NULL,p_account_id uuid DEFAULT NULL,p_category_id uuid DEFAULT NULL,
  p_counterparty_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $$
DECLARE rows jsonb; result jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501'; END IF;
  PERFORM briskers.require_permission(p_business_id,'expenses.read');
  rows := public.briskers_list_transactions_v2(p_business_id,p_limit,p_offset,
    p_start_date,p_end_date,p_search,p_direction,p_account_id,p_category_id,p_counterparty_id);
  SELECT coalesce(jsonb_agg(e.value || jsonb_build_object(
    'business_id',t.business_id,'row_version',t.row_version,
    'account_id',t.account_id,'category_id',t.category_id,'counterparty_id',t.vendor_id,
    'recurring_rule_id',t.recurring_rule_id,'recurring_occurrence_date',t.recurring_occurrence_date
  ) ORDER BY e.ordinality),'[]'::jsonb) INTO result
  FROM jsonb_array_elements(rows) WITH ORDINALITY e(value,ordinality)
  JOIN briskers.financial_transactions t ON t.business_id=p_business_id AND t.id=(e.value->>'id')::uuid;
  IF jsonb_array_length(result)<>jsonb_array_length(rows) THEN
    RAISE EXCEPTION 'Transaction list identity mismatch';
  END IF;
  RETURN result;
END;
$$;
REVOKE ALL ON FUNCTION public.briskers_list_transactions_recurring_v1(uuid,integer,integer,date,date,text,text,uuid,uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.briskers_list_transactions_recurring_v1(uuid,integer,integer,date,date,text,text,uuid,uuid,uuid) TO authenticated;
COMMIT;
