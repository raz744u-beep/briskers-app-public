import {PGlite} from '@electric-sql/pglite';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const db=new PGlite();
const shop='00000000-0000-0000-0000-000000000001', invoice='00000000-0000-0000-0000-000000000002', receipt='00000000-0000-0000-0000-000000000003', method='00000000-0000-0000-0000-000000000004', op='00000000-0000-0000-0000-000000000005';
await db.exec(`CREATE SCHEMA briskers; CREATE SCHEMA auth; CREATE ROLE anon; CREATE ROLE authenticated;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS $$SELECT '${shop}'::uuid$$;
CREATE FUNCTION briskers.is_owner(uuid) RETURNS boolean LANGUAGE sql AS $$SELECT COALESCE(current_setting('test.owner',true),'yes')='yes'$$;
CREATE FUNCTION briskers.require_permission(uuid,text) RETURNS void LANGUAGE sql AS $$SELECT$$;
CREATE TABLE briskers.sales_documents(id uuid,business_id uuid,kind text,status text,total_amount numeric,closed_at timestamptz);
CREATE TABLE briskers.invoice_pending_payments(id uuid,business_id uuid,invoice_id uuid,amount numeric,payment_method_id uuid,payment_date date,entered_at timestamptz);
CREATE TABLE briskers.invoice_payment_operation_keys(business_id uuid,operation_id uuid,invoice_id uuid,pending_payment_id uuid);
CREATE TABLE briskers.financial_transactions(id uuid,business_id uuid,status text);
CREATE TABLE briskers.payment_allocations(transaction_id uuid,business_id uuid,document_id uuid,gross_amount numeric);
CREATE FUNCTION public.briskers_finalize_pending_invoice_payment(uuid,uuid) RETURNS uuid LANGUAGE plpgsql AS $$DECLARE tx uuid:=gen_random_uuid(); BEGIN INSERT INTO briskers.financial_transactions VALUES(tx,$1,'posted'); INSERT INTO briskers.payment_allocations SELECT tx,$1,$2,sum(amount) FROM briskers.invoice_pending_payments WHERE business_id=$1 AND invoice_id=$2; DELETE FROM briskers.invoice_pending_payments WHERE business_id=$1 AND invoice_id=$2; RETURN tx; END$$;
CREATE FUNCTION public.briskers_close_invoice(uuid,uuid) RETURNS void LANGUAGE plpgsql AS $$BEGIN IF EXISTS(SELECT 1 FROM briskers.invoice_pending_payments WHERE business_id=$1 AND invoice_id=$2) THEN PERFORM public.briskers_finalize_pending_invoice_payment($1,$2); END IF; UPDATE briskers.sales_documents SET closed_at=now() WHERE business_id=$1 AND id=$2; END$$;
INSERT INTO briskers.sales_documents VALUES('${invoice}','${shop}','invoice','issued',100,NULL);
INSERT INTO briskers.invoice_pending_payments VALUES('${receipt}','${shop}','${invoice}',100,'${method}','2026-11-10',now());`);
await db.exec(readFileSync(new URL('../../review/offline_invoice_finalization_v1.sql',import.meta.url),'utf8'));
const request={total_cents:10000,paid_cents:0,close:true,receipts:[{id:receipt,operation_id:null,amount_cents:10000,method_id:method,payment_date:'2026-11-10'}]};
const call=(r=request,key=op)=>db.query('SELECT public.briskers_finalize_invoice_once_v1($1,$2,$3,$4) AS result',[shop,invoice,key,r]);
await assert.rejects(()=>call({...request,total_cents:9999}),e=>e.code==='40001');
await assert.rejects(()=>call({...request,receipts:[]}),e=>e.code==='40001');
await assert.rejects(()=>call({...request,receipts:[{...request.receipts[0],amount_cents:9999}]}),e=>e.code==='40001');
await db.exec("SELECT set_config('test.owner','no',false)");
await assert.rejects(()=>call(),e=>e.code==='42501');
await db.exec("SELECT set_config('test.owner','yes',false)");
const first=(await call()).rows; const second=(await call()).rows;
assert.deepEqual(first,second);
assert.equal((await db.query('SELECT count(*)::int AS n FROM briskers.financial_transactions')).rows[0].n,1);
await assert.rejects(()=>call({...request,close:false}),e=>e.code==='23505');
assert.equal((await db.query('SELECT count(*)::int AS n FROM briskers.invoice_finalization_operations_v1')).rows[0].n,1);
// The local-first close queue must use an empty receipt set. The locked RPC
// closes the document without modifying any existing payment/allocation row.
const closeOnly={total_cents:10000,paid_cents:10000,receipts:[],close:true};
const financial=async()=>({transactions:(await db.query('SELECT * FROM briskers.financial_transactions ORDER BY id')).rows,
  allocations:(await db.query('SELECT * FROM briskers.payment_allocations ORDER BY transaction_id')).rows,
  pending:(await db.query('SELECT * FROM briskers.invoice_pending_payments ORDER BY id')).rows});
const history=await financial();
await db.exec('UPDATE briskers.sales_documents SET closed_at=NULL');
await call(closeOnly,method); await call(closeOnly,method);
assert.deepEqual(await financial(),history);
assert.ok((await db.query('SELECT closed_at FROM briskers.sales_documents')).rows[0].closed_at);
// Mixed existing posted payments and a new partial receipt remain distinct.
await db.exec(`UPDATE briskers.sales_documents SET total_amount=200,closed_at=NULL;
INSERT INTO briskers.invoice_pending_payments VALUES('${receipt}','${shop}','${invoice}',30,'${method}','2026-11-10',now());
INSERT INTO briskers.invoice_payment_operation_keys VALUES('${shop}','${receipt}','${invoice}','${receipt}');`);
const partial={total_cents:20000,paid_cents:10000,close:false,receipts:[{...request.receipts[0],id:null,operation_id:receipt,amount_cents:3000}]};
await assert.rejects(()=>call({...partial,close:true},receipt),e=>e.code==='55000');
assert.equal((await db.query('SELECT count(*)::int AS n FROM briskers.invoice_pending_payments')).rows[0].n,1);
await call(partial,receipt); await call(partial,receipt);
assert.equal((await db.query('SELECT sum(gross_amount)::int AS n FROM briskers.payment_allocations')).rows[0].n,130);
assert.equal((await db.query('SELECT count(*)::int AS n FROM briskers.financial_transactions')).rows[0].n,2);
await db.close(); console.log('PASS: exact receipts, changed totals, Owner authorization, duplicate retry, operation conflict; isolated database only');
