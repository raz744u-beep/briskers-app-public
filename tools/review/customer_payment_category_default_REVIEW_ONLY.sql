-- REVIEW ONLY. Not a deployed migration. No historical row updates.
-- Source inspected read-only 2026-10-22. Preserve RPC identity, ACL and all
-- existing authorization, amount/allocation and idempotent replay behavior.
DO $review$
DECLARE source text; revised text;
BEGIN
  source := pg_get_functiondef('public.briskers_record_payment(uuid,uuid,uuid,numeric,uuid,date,uuid)'::regprocedure);
  IF md5(source) = '71ef1031501d03ac657ee243b4dface9' THEN RETURN; END IF;
  IF md5(source) <> 'afbdd96898e35cc1165db1848f55f97d' THEN
    RAISE EXCEPTION 'Payment RPC source drift; stop for review';
  END IF;
  revised := replace(source, 'DECLARE d briskers.sales_documents;',
    'DECLARE v_customer_category uuid; v_category_count integer; d briskers.sales_documents;');
  revised := replace(revised,
    ' INSERT INTO briskers.financial_transactions(business_id,account_id,kind,amount,currency_code,transaction_date,customer_id,payment_method_id,idempotency_key)',
    E' SELECT count(*), (array_agg(c.id))[1] INTO v_category_count,v_customer_category\r\n FROM briskers.financial_categories c\r\n WHERE c.business_id=p_business_id AND c.active\r\n AND lower(btrim(c.name))=''customers'' AND c.normal_direction=''income''\r\n AND c.report_treatment=''revenue'';\r\n IF v_category_count<>1 THEN\r\n  RAISE EXCEPTION ''Exactly one active Customers income category is required''\r\n    USING ERRCODE=''23514'';\r\n END IF;\r\n INSERT INTO briskers.financial_transactions(business_id,account_id,kind,amount,currency_code,transaction_date,customer_id,payment_method_id,idempotency_key,category_id)');
  revised := replace(revised,
    'd.customer_id,p_method_id,p_idempotency_key) RETURNING',
    'd.customer_id,p_method_id,p_idempotency_key,v_customer_category) RETURNING');
  IF md5(revised) <> '71ef1031501d03ac657ee243b4dface9' THEN
    RAISE EXCEPTION 'Unexpected category patch output';
  END IF;
  EXECUTE revised;
END;
$review$;
