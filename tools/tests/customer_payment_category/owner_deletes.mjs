import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { PGlite } from '@electric-sql/pglite';

const db = new PGlite();
const id = n => '00000000-0000-0000-0000-' + String(n).padStart(12, '0');
const shop = id(1);
const other = id(2);

try {
  await db.exec(
    "CREATE ROLE anon; CREATE ROLE authenticated; CREATE SCHEMA auth; CREATE SCHEMA briskers;" +
    "CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ " +
    "SELECT nullif(current_setting('test.actor',true),'')::uuid $$;" +
    "CREATE FUNCTION briskers.is_owner(b uuid) RETURNS bool LANGUAGE sql STABLE AS $$ " +
    "SELECT b::text=current_setting('test.shop',true) AND current_setting('test.owner',true)='true' $$;" +
    "CREATE TABLE briskers.financial_transactions(id uuid PRIMARY KEY,business_id uuid,kind text,job_id uuid);" +
    "CREATE TABLE briskers.sync_applied_operations(business_id uuid,operation_id text,entity_type text,result jsonb," +
    "PRIMARY KEY(business_id,operation_id));" +
    "CREATE TABLE briskers.payment_allocations(business_id uuid,transaction_id uuid);" +
    "CREATE TABLE briskers.appointments(id uuid PRIMARY KEY,business_id uuid,job_id uuid,request_id uuid);" +
    "CREATE TABLE briskers.appointment_create_operations(business_id uuid,operation_id uuid,appointment_id uuid," +
    "PRIMARY KEY(business_id,operation_id));" +
    "CREATE TABLE briskers.sales_documents(id uuid PRIMARY KEY,business_id uuid,kind text,source_estimate_id uuid);" +
    "CREATE TABLE briskers.sales_document_estimate_links(business_id uuid,estimate_id uuid);" +
    "CREATE FUNCTION public.briskers_delete_appointment(b uuid,a uuid) RETURNS void LANGUAGE plpgsql AS $$ BEGIN " +
    "IF EXISTS(SELECT 1 FROM briskers.appointments WHERE business_id=b AND id=a AND (job_id IS NOT NULL OR request_id IS NOT NULL)) " +
    "THEN RAISE EXCEPTION 'linked' USING ERRCODE='23514'; END IF; " +
    "DELETE FROM briskers.appointments WHERE business_id=b AND id=a; END $$;" +
    "CREATE FUNCTION public.briskers_delete_estimate(b uuid,e uuid) RETURNS bool LANGUAGE sql AS $$ " +
    "WITH removed AS (DELETE FROM briskers.sales_documents WHERE business_id=b AND id=e AND kind='estimate' RETURNING id) " +
    "SELECT EXISTS(SELECT 1 FROM removed) $$;"
  );
  await db.query("SELECT set_config('test.actor',$1,false),set_config('test.shop',$2,false),set_config('test.owner','true',false)", [id(3), shop]);
  for (const file of [
    '20261125163000_owner_standalone_expense_delete.sql',
    '20261125163100_owner_appointment_delete_identity.sql',
    '20261125163200_owner_estimate_delete_identity.sql',
  ]) {
    await db.exec(readFileSync(new URL('../../../supabase/migrations/' + file, import.meta.url), 'utf8'));
  }

  const expense = (uuid, op, preserve = []) => db.query(
    'SELECT public.briskers_delete_standalone_expense_v1($1,$2,$3,$4) AS id',
    [shop, uuid, op, preserve],
  ).then(result => result.rows[0].id);
  const financialCreate = (op, uuid) => db.query(
    "INSERT INTO briskers.sync_applied_operations VALUES($1,$2,'financial_transaction_create',jsonb_build_object('transaction_id',$3::text))",
    [shop, op, uuid],
  );
  await db.query("INSERT INTO briskers.financial_transactions VALUES($1,$2,'other_expense',NULL),($3,$2,'other_expense',$4),($5,$6,'other_expense',NULL)",
    [id(10), shop, id(11), id(30), id(12), other]);
  await financialCreate('financial-create-accepted', id(10));
  assert.equal(await expense(null, 'financial-create-accepted', [id(10)]), null);
  assert.equal(await expense(null, 'financial-create-accepted'), id(10));
  assert.equal(await expense(null, 'financial-create-accepted'), id(10));
  assert.equal(await expense(null, 'financial-create-canceled'), null);
  await assert.rejects(() => financialCreate('financial-create-canceled', id(99)), {code: 'PT409'});
  await assert.rejects(() => expense(id(11), null), {code: 'PT409'});
  const feed = (await db.query('SELECT transaction_id FROM public.briskers_expense_deletion_feed_v1($1,0)', [shop])).rows;
  assert.deepEqual(feed, [{transaction_id: id(10)}]);
  assert.deepEqual((await db.query('SELECT id FROM briskers.financial_transactions ORDER BY id')).rows,
    [{id: id(11)}, {id: id(12)}]);

  const appointment = (uuid, op) => db.query(
    'SELECT public.briskers_delete_appointment_identity_v1($1,$2,$3) AS id',
    [shop, uuid, op],
  ).then(result => result.rows[0].id);
  await db.query('INSERT INTO briskers.appointments VALUES($1,$2,NULL,NULL),($3,$2,$4,NULL)',
    [id(20), shop, id(21), id(30)]);
  await db.query('INSERT INTO briskers.appointment_create_operations VALUES($1,$2,$3)', [shop, id(22), id(20)]);
  assert.equal(await appointment(null, id(22)), id(20));
  assert.equal(await appointment(null, id(22)), id(20));
  assert.equal(await appointment(null, id(23)), null);
  await assert.rejects(() => db.query('INSERT INTO briskers.appointment_create_operations VALUES($1,$2,NULL)',
    [shop, id(23)]), {code: 'PT409'});
  await assert.rejects(() => appointment(id(21), null), {code: '23514'});

  const estimate = uuid => db.query('SELECT public.briskers_owner_delete_estimate_v1($1,$2)', [shop, uuid]);
  await db.query("INSERT INTO briskers.sales_documents VALUES($1,$2,'estimate',NULL),($3,$2,'estimate',NULL),($4,$2,'invoice',$3)",
    [id(40), shop, id(41), id(42)]);
  await estimate(id(40));
  await estimate(id(40));
  await estimate(id(43));
  await assert.rejects(() => db.query("INSERT INTO briskers.sales_documents VALUES($1,$2,'estimate',NULL)",
    [id(43), shop]), {code: 'PT409'});
  await assert.rejects(() => estimate(id(41)), {code: 'PT409'});
  assert.deepEqual((await db.query('SELECT estimate_id FROM public.briskers_estimate_deletion_feed_v1($1,0)', [shop])).rows,
    [{estimate_id: id(40)}, {estimate_id: id(43)}]);

  await db.exec("SELECT set_config('test.owner','false',false)");
  for (const run of [() => expense(id(12), null), () => appointment(id(21), null), () => estimate(id(41))]) {
    await assert.rejects(run, {code: '42501'});
  }
  console.log('PASS: Owner delete authorization, identity cancellation, retry and linked-record protection.');
} finally {
  await db.close();
}
