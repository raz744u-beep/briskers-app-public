-- Execute the deployed RPC bodies against temporary synthetic relations only.
-- Permission lookup is replaced with a strict fixture-business check; the real
-- auth-required entry guard is tested separately. Everything rolls back.
BEGIN;
CREATE TEMP TABLE sales_document_lines(id uuid,business_id uuid,document_id uuid,
  item_id uuid,line_kind text,name text,description text,quantity numeric,
  unit_price numeric,tax_rate numeric,net_amount numeric,tax_amount numeric,
  updated_at timestamptz,row_version bigint,pricing_unit text);
CREATE TEMP TABLE sales_documents(id uuid,business_id uuid,kind text,origin text,
  status text,closed_at timestamptz,source_estimate_id uuid,row_version bigint,
  updated_at timestamptz,net_amount numeric,tax_amount numeric,total_amount numeric);
CREATE TEMP TABLE catalog_items(id uuid,business_id uuid,active boolean,pricing_unit text);
CREATE FUNCTION pg_temp.require_permission(business uuid, permission text)
RETURNS void LANGUAGE plpgsql AS $$ BEGIN
  IF business IS DISTINCT FROM '00000000-0000-0000-0000-000000000001'::uuid
      OR permission NOT IN ('invoices.edit','estimates.edit') THEN
    RAISE insufficient_privilege;
  END IF;
END $$;
CREATE FUNCTION pg_temp.recalculate_native_document(business uuid, document uuid)
RETURNS void LANGUAGE sql AS $$
  UPDATE pg_temp.sales_documents SET
    net_amount=(SELECT sum(net_amount) FROM pg_temp.sales_document_lines WHERE document_id=document),
    tax_amount=(SELECT sum(tax_amount) FROM pg_temp.sales_document_lines WHERE document_id=document),
    total_amount=(SELECT sum(net_amount+tax_amount) FROM pg_temp.sales_document_lines WHERE document_id=document)
  WHERE business_id=business AND id=document
$$;
DO $$ DECLARE body text; BEGIN
  body:=pg_get_functiondef('public.briskers_update_document_line_v2(uuid,uuid,bigint,text,numeric,numeric,numeric,text,text)'::regprocedure);
  body:=replace(replace(body,'public.briskers_update_document_line_v2','pg_temp.briskers_update_document_line_v2'),'briskers.','pg_temp.');
  EXECUTE body;
  body:=pg_get_functiondef('public.briskers_replace_document_line_catalog_v1(uuid,uuid,bigint,text,numeric,numeric,numeric,text,text,uuid)'::regprocedure);
  body:=replace(body,'public.briskers_replace_document_line_catalog_v1','pg_temp.briskers_replace_document_line_catalog_v1');
  body:=replace(replace(body,'public.briskers_update_document_line_v2','pg_temp.briskers_update_document_line_v2'),'briskers.','pg_temp.');
  EXECUTE body;
END $$;
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000009',true);
INSERT INTO pg_temp.sales_documents(id,business_id,kind,origin,status,row_version)
VALUES('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000001','invoice','native','draft',1);
INSERT INTO pg_temp.sales_document_lines(id,business_id,document_id,item_id,line_kind,name,quantity,unit_price,tax_rate,row_version)
VALUES('00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000004','item','Wrong part',2,10,0,1);
INSERT INTO pg_temp.catalog_items VALUES
('00000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000001',true,'each'),
('00000000-0000-0000-0000-000000000006','00000000-0000-0000-0000-000000000008',true,'foreign'),
('00000000-0000-0000-0000-000000000007','00000000-0000-0000-0000-000000000001',false,'inactive');
DO $$ DECLARE
  business uuid:='00000000-0000-0000-0000-000000000001';
  line uuid:='00000000-0000-0000-0000-000000000003';
  item uuid:='00000000-0000-0000-0000-000000000005';
  result boolean;
BEGIN
  result:=pg_temp.briskers_replace_document_line_catalog_v1(business,line,1,'Correct part',2,30,.1,'Correct catalog selection','item',item);
  ASSERT result;
  ASSERT (SELECT count(*)=1 AND min(item_id::text)=item::text AND min(quantity)=2 AND min(pricing_unit)='each' FROM pg_temp.sales_document_lines);
  ASSERT (SELECT total_amount=66 AND row_version=2 FROM pg_temp.sales_documents);
  BEGIN
    PERFORM pg_temp.briskers_replace_document_line_catalog_v1(business,line,1,'Stale edit',2,99,0,null,'item',item);
    RAISE EXCEPTION 'Stale edit accepted';
  EXCEPTION WHEN SQLSTATE 'PT409' THEN NULL; END;
  BEGIN
    PERFORM pg_temp.briskers_replace_document_line_catalog_v1(business,line,2,'Foreign item',2,99,0,null,'item','00000000-0000-0000-0000-000000000006');
    RAISE EXCEPTION 'Foreign catalog accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    PERFORM pg_temp.briskers_replace_document_line_catalog_v1(business,line,2,'Inactive item',2,99,0,null,'item','00000000-0000-0000-0000-000000000007');
    RAISE EXCEPTION 'Inactive catalog accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  ASSERT (SELECT name='Correct part' AND unit_price=30 FROM pg_temp.sales_document_lines);
  -- Existing unpaid imported-invoice editability is preserved.
  UPDATE pg_temp.sales_documents SET origin='mobilebiz';
  PERFORM pg_temp.briskers_replace_document_line_catalog_v1(business,line,2,'Correct part',2,30,.1,null,'item',item);
  ASSERT (SELECT row_version=3 FROM pg_temp.sales_documents);
  UPDATE pg_temp.sales_document_lines SET name='Labor',line_kind='item';
  BEGIN
    PERFORM pg_temp.briskers_replace_document_line_catalog_v1(business,line,3,'Part',2,30,0,null,'item',item);
    RAISE EXCEPTION 'Labor identity retired';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  UPDATE pg_temp.sales_documents SET closed_at=clock_timestamp();
  BEGIN
    PERFORM pg_temp.briskers_replace_document_line_catalog_v1(business,line,3,'Labor',2,30,0,null,'labor',item);
    RAISE EXCEPTION 'Closed document edited';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
END $$;
ROLLBACK;
SELECT 'Replacement, totals, stable identity, stale version, shop isolation, inactive items, legacy editability, labor and closed guards passed on synthetic relations; rolled back' AS result;
