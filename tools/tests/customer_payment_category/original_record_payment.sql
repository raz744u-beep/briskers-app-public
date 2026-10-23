CREATE OR REPLACE FUNCTION public.briskers_record_payment(p_business_id uuid, p_invoice_id uuid, p_account_id uuid, p_amount numeric, p_idempotency_key uuid, p_date date DEFAULT CURRENT_DATE, p_method_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE d briskers.sales_documents; x briskers.financial_transactions; tx uuid; paid numeric; taxpaid numeric; remaining numeric; taxshare numeric; credits numeric; credittax numeric;
BEGIN
 PERFORM briskers.require_permission(p_business_id,'payments.create');
 IF p_amount IS NULL OR p_amount<=0 OR p_amount>999999999999.99 OR p_amount<>round(p_amount,2) OR p_idempotency_key IS NULL THEN RAISE EXCEPTION 'A positive cent amount and idempotency key are required' USING ERRCODE='22023'; END IF;
 PERFORM briskers.lock_operation(p_business_id,p_idempotency_key);
 SELECT * INTO x FROM briskers.financial_transactions WHERE business_id=p_business_id AND idempotency_key=p_idempotency_key;
 IF FOUND THEN
  IF x.kind='customer_payment' AND x.account_id=p_account_id AND x.amount=p_amount AND x.transaction_date=p_date AND x.payment_method_id IS NOT DISTINCT FROM p_method_id AND EXISTS(SELECT 1 FROM briskers.payment_allocations a WHERE a.business_id=p_business_id AND a.transaction_id=x.id AND a.document_id=p_invoice_id AND a.gross_amount=p_amount) THEN RETURN x.id; END IF;
  RAISE EXCEPTION 'Idempotency key was already used for a different operation' USING ERRCODE='23505';
 END IF;
 SELECT * INTO d FROM briskers.sales_documents WHERE business_id=p_business_id AND id=p_invoice_id FOR UPDATE;
 IF NOT FOUND OR d.kind<>'invoice' OR d.status NOT IN ('issued','accepted') THEN RAISE EXCEPTION 'Payment requires an issued invoice' USING ERRCODE='23514'; END IF;
 SELECT COALESCE(sum(a.gross_amount),0),COALESCE(sum(a.tax_amount),0) INTO paid,taxpaid FROM briskers.payment_allocations a JOIN briskers.financial_transactions t ON t.business_id=a.business_id AND t.id=a.transaction_id
 WHERE a.business_id=p_business_id AND a.document_id=p_invoice_id AND t.status='posted';
 SELECT COALESCE(sum(total_amount),0),COALESCE(sum(tax_amount),0) INTO credits,credittax FROM briskers.sales_documents WHERE business_id=p_business_id AND credited_invoice_id=p_invoice_id AND status IN ('issued','accepted');
 remaining:=d.total_amount-credits-paid;
 IF p_amount>remaining THEN RAISE EXCEPTION 'Payment exceeds invoice balance; use a separate unapplied customer credit workflow' USING ERRCODE='23514'; END IF;
 IF p_amount=remaining THEN taxshare:=d.tax_amount-credittax-taxpaid;
 ELSE taxshare:=round(p_amount*(d.tax_amount-credittax)/NULLIF(d.total_amount-credits,0),2); END IF;
 INSERT INTO briskers.financial_transactions(business_id,account_id,kind,amount,currency_code,transaction_date,customer_id,payment_method_id,idempotency_key)
 VALUES(p_business_id,p_account_id,'customer_payment',p_amount,d.currency_code,p_date,d.customer_id,p_method_id,p_idempotency_key) RETURNING id INTO tx;
 INSERT INTO briskers.payment_allocations(business_id,transaction_id,document_id,gross_amount,tax_amount) VALUES(p_business_id,tx,p_invoice_id,p_amount,taxshare);
 RETURN tx;
END $function$
