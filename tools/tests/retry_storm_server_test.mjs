// Isolated WASM Postgres only. Never opens a Supabase connection.
import {PGlite} from './customer_payment_category/node_modules/@electric-sql/pglite/dist/index.js';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const db=new PGlite();
const sql=readFileSync(new URL('../review/nonretryable_business_conflicts.sql',import.meta.url),'utf8');
const fixture=readFileSync(new URL('retry_storm_original_functions.sql',import.meta.url),'utf8');
const manifest=[...sql.matchAll(/\('public\.([^']+)','([a-f0-9]{32})','([a-f0-9]{32})'\)/g)].map(m=>({signature:m[1],old:m[2],patched:m[3]}));
assert.equal(manifest.length,27);
const shop='00000000-0000-0000-0000-000000000001';
const doc='00000000-0000-0000-0000-000000000002';
const appt='00000000-0000-0000-0000-000000000003';
const op='00000000-0000-0000-0000-000000000004';
const actualNames=['briskers_issue_document','briskers_save_invoice_mileage_out_v1','briskers_sync_offline_appointment_delete'];
try {
await db.exec(`CREATE SCHEMA briskers;
CREATE TABLE briskers.sales_documents(id uuid,business_id uuid,kind text,origin text,status text,row_version bigint,closed_at timestamptz,mileage_schema_version int);
CREATE TABLE briskers.appointments(id uuid,business_id uuid,row_version bigint);
CREATE TABLE briskers.appointment_delete_operations(business_id uuid,operation_id uuid,appointment_id uuid,base_version bigint,completed_at timestamptz,PRIMARY KEY(business_id,operation_id));
CREATE FUNCTION briskers.require_permission(uuid,text) RETURNS void LANGUAGE plpgsql AS $$BEGIN IF current_setting('test.denied',true)='yes' THEN RAISE EXCEPTION 'denied' USING ERRCODE='42501'; END IF; END$$;
CREATE FUNCTION briskers.is_owner(uuid) RETURNS boolean LANGUAGE sql AS $$SELECT coalesce(current_setting('test.denied',true),'no')<>'yes'$$;
INSERT INTO briskers.sales_documents VALUES('${doc}','${shop}','invoice','native','issued',8,NULL,2);
INSERT INTO briskers.appointments VALUES('${appt}','${shop}',8);`);
await db.exec(fixture);
for(const item of manifest) {
  const name=item.signature.split('(')[0];
  if(actualNames.includes(name)) continue;
  await db.exec(`CREATE FUNCTION public.${item.signature} RETURNS void LANGUAGE plpgsql AS $$BEGIN RAISE EXCEPTION 'test business conflict' USING ERRCODE='40001'; END$$;`);
}
// Production patch rejects mismatched definitions atomically. No partial update.
await assert.rejects(()=>db.exec(sql),e=>/Definition changed/.test(e.message));
let checked=sql;
const before=(await db.query(`SELECT oid,proname,prosrc,proowner,proacl,prosecdef,proconfig FROM pg_proc WHERE pronamespace='public'::regnamespace ORDER BY oid`)).rows;
for(const item of manifest) {
 const live=(await db.query(`SELECT md5(pg_get_functiondef($1::regprocedure)) old,md5(replace(pg_get_functiondef($1::regprocedure),'''40001''','''PT409''')) patched`,['public.'+item.signature])).rows[0];
 checked=checked.replace(item.old,live.old).replace(item.patched,live.patched);
}
const invoke=[
 `SELECT public.briskers_sync_offline_appointment_delete('${shop}','${appt}','${op}',7)`,
 `SELECT public.briskers_sync_offline_appointment_delete('${shop}','00000000-0000-0000-0000-000000000099','${op}',7)`,
 `SELECT public.briskers_save_invoice_mileage_out_v1('${shop}','${doc}',7,12345)`,
 `SELECT public.briskers_issue_document('${shop}','${doc}',7)`
];
for(const call of invoke) await assert.rejects(()=>db.exec(call),e=>e.code==='40001');
await db.exec(checked);
await db.exec(checked); // Exact already-patched definitions are accepted.
for(const call of invoke) await assert.rejects(()=>db.exec(call),e=>e.code==='PT409');
const after=(await db.query(`SELECT oid,proname,prosrc,proowner,proacl,prosecdef,proconfig FROM pg_proc WHERE pronamespace='public'::regnamespace ORDER BY oid`)).rows;
assert.deepEqual(after,before.map(r=>({...r,prosrc:r.prosrc.replaceAll("'40001'","'PT409'")})));
assert.equal((await db.query('SELECT count(*)::int n FROM briskers.appointment_delete_operations')).rows[0].n,0);
assert.equal((await db.query('SELECT row_version FROM briskers.sales_documents')).rows[0].row_version,8);
assert.equal((await db.query('SELECT row_version FROM briskers.appointments')).rows[0].row_version,8);
await db.exec(`SET test.denied='yes'`);
for(const call of [invoke[0],invoke[2],invoke[3]]) await assert.rejects(()=>db.exec(call),e=>e.code==='42501');
console.log('PASS: 27-function atomic code-only patch, drift rejection, rerun, four real conflict paths, permission preservation, OIDs/ACLs/settings/security preserved, zero data changes');
} finally {await db.close();}
