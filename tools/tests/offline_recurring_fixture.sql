\set ON_ERROR_STOP on
CREATE ROLE anon;
CREATE ROLE authenticated;
CREATE SCHEMA briskers;
CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS
  $$ SELECT nullif(current_setting('test.actor',true),'')::uuid $$;
CREATE FUNCTION briskers.require_permission(b uuid,p text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF auth.uid() IS NULL OR b::text IS DISTINCT FROM current_setting('test.business',true) THEN
    RAISE EXCEPTION 'Denied' USING ERRCODE='42501';
  END IF;
END $$;
CREATE TABLE briskers.financial_accounts(id uuid PRIMARY KEY,business_id uuid,name text,active bool,currency_code text);
CREATE TABLE briskers.financial_categories(id uuid PRIMARY KEY,business_id uuid,name text,active bool,normal_direction text);
CREATE TABLE briskers.vendors(id uuid PRIMARY KEY,business_id uuid,name text,active bool);
CREATE TABLE briskers.recurring_transactions(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),business_id uuid NOT NULL,
  source_transaction_id uuid,direction text,vendor_id uuid,account_id uuid,category_id uuid,
  amount numeric,remarks text,frequency text,interval_count int,next_date date,end_date date,
  is_repeating bool,paused_reason text,created_by uuid,row_version bigint NOT NULL DEFAULT 1
);
CREATE TABLE briskers.financial_transactions(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),business_id uuid NOT NULL,account_id uuid,
  category_id uuid,kind text,amount numeric,currency_code text,transaction_date date,
  vendor_id uuid,remarks text,idempotency_key uuid,recurring_rule_id uuid,
  recurring_occurrence_date date,created_by uuid,row_version bigint NOT NULL DEFAULT 1,
  status text NOT NULL DEFAULT 'posted'
);
CREATE UNIQUE INDEX uq_recurring_occurrence ON briskers.financial_transactions
  (business_id,recurring_rule_id,recurring_occurrence_date)
  WHERE recurring_rule_id IS NOT NULL AND recurring_occurrence_date IS NOT NULL;
CREATE TABLE briskers.expense_allocations(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),business_id uuid,transaction_id uuid,
  category_id uuid,amount numeric,created_by uuid
);
CREATE FUNCTION briskers.test_touch() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='UPDATE' THEN NEW.row_version:=OLD.row_version+1; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER touch BEFORE UPDATE ON briskers.recurring_transactions FOR EACH ROW EXECUTE FUNCTION briskers.test_touch();
CREATE TRIGGER touch BEFORE UPDATE ON briskers.financial_transactions FOR EACH ROW EXECUTE FUNCTION briskers.test_touch();
CREATE FUNCTION public.briskers_transaction_detail(b uuid,t uuid) RETURNS jsonb LANGUAGE sql STABLE AS
  $$ SELECT to_jsonb(ft)||jsonb_build_object('attachments','[]'::jsonb)
       FROM briskers.financial_transactions ft WHERE business_id=b AND id=t $$;
CREATE FUNCTION public.briskers_transaction_options(b uuid) RETURNS jsonb LANGUAGE sql STABLE AS
  $$ SELECT jsonb_build_object('accounts',(SELECT jsonb_agg(to_jsonb(a)) FROM briskers.financial_accounts a WHERE business_id=b),
    'categories',(SELECT jsonb_agg(to_jsonb(c)) FROM briskers.financial_categories c WHERE business_id=b),
    'counterparties',(SELECT jsonb_agg(to_jsonb(v)) FROM briskers.vendors v WHERE business_id=b)) $$;
INSERT INTO briskers.financial_accounts VALUES
 ('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000001','Checking',true,'USD');
INSERT INTO briskers.financial_categories VALUES
 ('00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000001','Supplies',true,'expense');
INSERT INTO briskers.vendors VALUES
 ('00000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000001','Synthetic vendor',true);
