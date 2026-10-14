// Synthetic in-memory contract test. Never connects to the Briskers database.
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const {PGlite} = await import(process.env.PGLITE_MODULE ?? '@electric-sql/pglite');
const db = new PGlite();
let checks=0;
const b='00000000-0000-0000-0000-000000000001';
const j='00000000-0000-0000-0000-000000000018';
const i='00000000-0000-0000-0000-000000000101';
const op='00000000-0000-0000-0000-000000000201';
const owner='00000000-0000-0000-0000-000000000301';
const snapshot={schema_version:2,business_id:b,job_id:j,job_number:'J-SYNTHETIC',
  inventory_complete:true,write_fences_verified:true,can_retire:true,
  blocked_reasons:[],estimates_preserved:[],invoices:[{id:i,business_id:b,job_id:j,kind:'invoice',
  origin:'native',status:'draft',has_financial_history:false,
  has_pending_operations:false,has_protected_history:false}]};
const set = async (key,value) => db.query('select set_config($1,$2,false)',[key,value]);
const execute=async(s=snapshot,operation=op,job=j)=>db.query(
 'select public.briskers_job_retirement_execute_v2($1,$2,$3,$4::jsonb) as receipt',
 [b,job,operation,JSON.stringify(s)]);
const rejects=async(fn,pattern)=>{await assert.rejects(fn,pattern);checks++;};
try {
 await db.exec(`create schema briskers; create schema auth;
 create role anon; create role authenticated;
 create function auth.uid() returns uuid language sql stable as
 $$select nullif(current_setting('test.user',true),'')::uuid$$;
 create function briskers.is_owner(uuid) returns boolean language sql stable as
 $$select current_setting('test.owner',true)='yes'
 and $1::text=current_setting('test.business',true)$$;`);
 await set('test.user',owner); await set('test.owner','yes'); await set('test.business',b);
 await db.exec(readFileSync('tools/proposals/owner_job_retirement_v2.sql','utf8'));
 await rejects(()=>execute(),/dependency adapter is not deployed/);
 await db.exec(`create function briskers.job_retirement_verified_snapshot_v2(uuid,uuid)
 returns jsonb language sql as $$select current_setting('test.snapshot')::jsonb$$;`);
 const reset=async(s=snapshot)=>set('test.snapshot',JSON.stringify(s));
 await reset();
 await set('test.owner','no');await rejects(()=>execute(),/Owner access required/);
 await set('test.owner','');await rejects(()=>execute(),/Owner access required/);
 await set('test.owner','yes');await set('test.user','');
 await rejects(()=>execute(),/Owner access required/);await set('test.user',owner);
 await set('test.business',j);await rejects(()=>execute(),/Owner access required/);
 await set('test.business',b);
 for(const key of ['inventory_complete','write_fences_verified','can_retire']) {
   const changed={...snapshot,[key]:false};await reset(changed);
   await rejects(()=>execute(changed),/Incomplete authoritative|protected history/);
 }
 await reset({...snapshot,invoices:[...snapshot.invoices,{...snapshot.invoices[0],id:j}]});
 await rejects(()=>execute(),/links changed/);
 for(const patch of [{business_id:j},{job_id:b},{id:null},{status:'paid'},{origin:'mobilebiz'},
   {has_financial_history:true},{has_pending_operations:true},{has_protected_history:true}]) {
   const changed={...snapshot,invoices:[{...snapshot.invoices[0],...patch}]};
   await reset(changed);await rejects(()=>execute(changed),/Protected linked invoice/);
   assert.equal((await db.query('select count(*)::int n from briskers.job_retirement_operations_v2')).rows[0].n,0);checks++;
 }
 await reset();const first=await execute();const again=await execute();
 assert.deepEqual(again.rows,first.rows);checks++;
 assert.equal((await db.query('select count(*)::int n from briskers.job_retirement_operations_v2')).rows[0].n,1);checks++;
 assert.equal((await db.query('select count(*)::int n from briskers.job_retirement_tombstones_v2')).rows[0].n,2);checks++;
 await rejects(()=>execute({...snapshot,job_number:'different'}),/Operation ID reused/);
 await rejects(()=>execute(snapshot,'00000000-0000-0000-0000-000000000202'),/already retired/);
 await rejects(()=>db.exec('delete from briskers.job_retirement_tombstones_v2'),/immutable/);
 await rejects(()=>db.exec('update briskers.job_retirement_operations_v2 set actor_id=actor_id'),/immutable/);
 const acl=await db.query("select has_function_privilege('authenticated','public.briskers_job_retirement_execute_v2(uuid,uuid,uuid,jsonb)','execute') allowed");
 assert.equal(acl.rows[0].allowed,false);checks++;
 const source=readFileSync('tools/proposals/owner_job_retirement_v2.sql','utf8');
 assert.ok(!/DELETE FROM briskers\.(jobs|sales_documents|payments|customers|expenses)/i.test(source));checks++;
 assert.ok(!source.includes('document_number_reuse'));checks++;
 console.log(`PASS ${checks} synthetic owner-retirement contract assertions. Deployment still gated; adapter deliberately absent.`);
} finally {await db.close();}
