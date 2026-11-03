// Run with Node 20+ and @electric-sql/pglite (validated with 0.5.9).
// PGLITE_MODULE may point to an already installed package dist/index.js.
// All schema and fixture changes are confined to a synthetic in-memory DB.
const { PGlite } = await import(process.env.PGLITE_MODULE ?? '@electric-sql/pglite');
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const db = new PGlite();
const business = '00000000-0000-0000-0000-000000000001';
const otherBusiness = '00000000-0000-0000-0000-000000000002';
const note = '00000000-0000-0000-0000-000000000010';
const general = '00000000-0000-0000-0000-000000000011';
const user = '00000000-0000-0000-0000-000000000100';
const passed = [];
await db.exec(`
  create schema briskers; create schema auth;
  create role anon; create role authenticated; create role service_role;
  create table briskers.document_note_templates (
    id uuid primary key, business_id uuid not null, name text not null,
    body text not null, template_type text not null default 'standard',
    show_in_quick_list boolean not null default true,
    active boolean not null default true, sort_order integer not null default 100,
    created_at timestamptz not null default clock_timestamp(),
    updated_at timestamptz not null default clock_timestamp(),
    row_version bigint not null default 1, created_by uuid,
    unique(business_id,name)
  );
  create function auth.uid() returns uuid language sql stable as
    $$select nullif(current_setting('test.user_id',true),'')::uuid$$;
  create function briskers.is_owner(id uuid) returns boolean language sql stable as
    $$select case when current_setting('test.owner',true)='null' then null::boolean
       else auth.uid() is not null and current_setting('test.owner',true)='yes'
       and id::text=current_setting('test.business',true) end$$;
  create function briskers.require_permission(id uuid, code text) returns void
    language plpgsql as $$begin
      if auth.uid() is null or id::text<>current_setting('test.business',true)
      then raise exception 'permission denied' using errcode='42501'; end if;
    end$$;
  select set_config('test.user_id','${user}',false);
  select set_config('test.owner','yes',false);
  select set_config('test.business','${business}',false);
  insert into briskers.document_note_templates(id,business_id,name,body,sort_order)
  values ('${note}','${business}','Warranty','Original body',100),
         ('${general}','${business}',' General ','General body',-100);
`);
// Recreate the real existing read RPC ACL before replacing its definition.
await db.exec(`create function public.briskers_document_note_templates(uuid,boolean default false)
  returns jsonb language sql as $$select '[]'::jsonb$$;
  grant execute on function public.briskers_document_note_templates(uuid,boolean) to authenticated, service_role;`);
const beforeAcl=(await db.query(`select proacl::text as acl from pg_proc
  where oid='public.briskers_document_note_templates(uuid,boolean)'::regprocedure`)).rows[0].acl;
const sql = readFileSync(new URL('../migrations/20261013001642_standard_note_styles_and_versioned_edits.sql', import.meta.url),'utf8');
await db.exec(sql); passed.push('migration applies to existing synthetic schema');
await db.exec(sql); passed.push('migration reapplication is safe');
const afterAcl=(await db.query(`select proacl::text as acl from pg_proc
  where oid='public.briskers_document_note_templates(uuid,boolean)'::regprocedure`)).rows[0].acl;
assert.equal(afterAcl,beforeAcl);passed.push('existing read RPC ACL is preserved exactly');
const list = (await db.query(`select public.briskers_document_note_templates($1) as notes`,[business])).rows[0].notes;
assert.deepEqual(list.map(x=>x.id),[note,general]);
assert.equal(list[0].color_hex,'#1565C0');
passed.push('legacy list signature, default color, and General-last order');
const patch = async (id,version,changes,b=business) => (await db.query(
  `select public.briskers_patch_document_note_template_v1($1,$2,$3,$4) as note`,[b,id,version,JSON.stringify(changes)])).rows[0].note;
let row = await patch(note,1,{body:'  Revised body  ',color_hex:'#c62828',sort_order:20});
assert.equal(row.body,'Revised body'); assert.equal(row.color_hex,'#C62828');
assert.equal(row.row_version,2); assert.equal(row.name,'Warranty');
passed.push('field-level edit/color/order and version increment');
async function fails(label,fn,code){
  try {await fn(); assert.fail(label+' unexpectedly succeeded');}
  catch(e){assert.equal(e.code,code,label+': '+e.message);passed.push(label);}
}
await fails('stale version does not overwrite text',()=>patch(note,1,{body:'Stale edit'}),'40001');
await fails('cross-business access denied',()=>patch(note,2,{body:'Wrong business'},otherBusiness),'42501');
await db.exec(`select set_config('test.owner','no',false)`);
await fails('non-owner edit denied',()=>patch(note,2,{body:'Non-owner'}),'42501');
await db.exec(`select set_config('test.owner','null',false)`);
await fails('null ownership helper result is denied',()=>patch(note,2,{body:'Null owner'}),'42501');
await db.exec(`select set_config('test.owner','yes',false)`);
await fails('null business is denied',()=>patch(note,2,{body:'Null business'},null),'42501');
await db.exec(`select set_config('test.user_id','',false)`);
await fails('unauthenticated edit denied',()=>patch(note,2,{body:'Anonymous'}),'42501');
await db.exec(`select set_config('test.user_id','${user}',false)`);
await fails('unsupported fields rejected',()=>patch(note,2,{business_id:otherBusiness}),'22023');
await fails('empty body rejected',()=>patch(note,2,{body:' '}),'22023');
await fails('invalid color rejected',()=>patch(note,2,{color_hex:'red'}),'22023');
await fails('General cannot be renamed by new RPC',()=>patch(general,1,{name:'Not General'}),'22023');
await fails('General cannot be renamed by legacy UPDATE',()=>db.exec(`update briskers.document_note_templates set name='Gone' where id='${general}'`),'22023');
await fails('case-insensitive duplicate rejected',()=>patch(note,2,{name:' GENERAL '}),'23505');
await fails('legacy INSERT cannot create duplicate General spelling',()=>db.exec(
  `insert into briskers.document_note_templates(id,business_id,name,body)
   values ('${user}','${business}','general','Duplicate General')`),'23505');
await fails('legacy UPDATE cannot create duplicate General spelling',()=>db.exec(
  `update briskers.document_note_templates set name='GENERAL' where id='${note}'`),'23505');
await fails('absent row rejected',()=>patch(user,1,{body:'Missing'}),'P0002');
row=await patch(note,2,{sort_order:5});
assert.equal(row.body,'Revised body');assert.equal(row.color_hex,'#C62828');
passed.push('order-only patch preserves body and color');
await db.exec(`update briskers.document_note_templates set active=false where id='${note}'`);
await fails('inactive note cannot be silently edited',()=>patch(note,3,{body:'Inactive'}),'22023');
const grants=(await db.query(`select
  has_function_privilege('anon','public.briskers_patch_document_note_template_v1(uuid,uuid,bigint,jsonb)','EXECUTE') as anon,
  has_function_privilege('authenticated','public.briskers_patch_document_note_template_v1(uuid,uuid,bigint,jsonb)','EXECUTE') as authenticated`)).rows[0];
assert.equal(grants.anon,false);assert.equal(grants.authenticated,true);passed.push('new RPC ACL restricts invocation to authenticated role');
const after=(await db.query(`select body,color_hex from briskers.document_note_templates where id=$1`,[note])).rows[0];
assert.equal(after.body,'Revised body');assert.equal(after.color_hex,'#C62828');
passed.push('all rejected operations leave saved values intact');

// Verify the independent category migration on the same synthetic schema.
const categorySql = readFileSync(new URL('../migrations/20261013_standard_note_categories.sql', import.meta.url), 'utf8');
await db.exec(`update briskers.document_note_templates set active=true where id='${note}'`);
await db.exec(categorySql);
let categories = (await db.query(`select public.briskers_document_note_templates($1) as notes`, [business])).rows[0].notes;
assert.equal(categories.find(x => x.id === note).category_key, 'warranty');
assert.equal(categories.find(x => x.id === general).category_key, 'general');
assert.equal(categories.find(x => x.id === note).body, 'Revised body');
passed.push('category migration preserves template text and classifies historical notes');
row = await patch(note, 3, {category_key:'service'});
assert.equal(row.category_key, 'service');
assert.equal(row.body, 'Revised body');
await db.exec(categorySql);
categories = (await db.query(`select public.briskers_document_note_templates($1) as notes`, [business])).rows[0].notes;
assert.equal(categories.find(x => x.id === note).category_key, 'service');
assert.equal(categories.find(x => x.id === note).body, 'Revised body');
passed.push('category migration is repeatable and preserves an Owner category choice');
await fails('invalid category rejected', () => patch(note,4,{category_key:'invalid'}), '22023');
await db.exec(`select set_config('test.owner','no',false)`);
await fails('Secretary cannot change template category', () => patch(note,4,{category_key:'advisory'}), '42501');
const secretaryRead = (await db.query(`select public.briskers_document_note_templates($1) as notes`, [business])).rows[0].notes;
assert.equal(secretaryRead.find(x => x.id === note).body, 'Revised body');
passed.push('Secretary can read exact saved note body');
await db.close();
console.log(JSON.stringify({passed:passed.length,checks:passed},null,2));
