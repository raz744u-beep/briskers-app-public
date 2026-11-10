import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const db = new PGlite();
const shop = '00000000-0000-4000-a000-000000000001';
const id = '00000000-0000-4000-a000-000000000002';
const edit = {id, name:'Cintas fixture', active:true, default_surcharge_percent:0};
const apply = (change, base=null, business=shop) => db.query(
  'select public.briskers_reconcile_counterparty_v1($1,$2,$3::jsonb,$4::jsonb)',
  [business,change.id,JSON.stringify(change),base === null ? null : JSON.stringify(base)]);
try {
  await db.exec(`create schema briskers; create schema auth;
    create role anon; create role authenticated;
    create function auth.uid() returns uuid language sql as $$select gen_random_uuid()$$;
    create table briskers.vendors(id uuid primary key,business_id uuid not null,name text,active boolean,
      created_by uuid,default_category_id uuid,default_surcharge_percent numeric default 0);
    create function briskers.require_permission(uuid,text) returns void language plpgsql as $$
      begin if current_setting('test.permitted',true) is distinct from 'yes' then raise exception 'denied'; end if; end $$;
    create function public.briskers_save_counterparty(uuid,uuid,text,boolean) returns void language sql as $$
      update briskers.vendors set name=$3,active=$4 where business_id=$1 and id=$2 $$;
    create function public.briskers_set_counterparty_default_category(uuid,uuid,uuid) returns void language sql as $$
      update briskers.vendors set default_category_id=$3 where business_id=$1 and id=$2 $$;
    create function public.briskers_set_counterparty_surcharge(uuid,uuid,numeric) returns void language sql as $$
      update briskers.vendors set default_surcharge_percent=$3 where business_id=$1 and id=$2 $$;`);
  await db.exec(readFileSync(new URL('../../migrations/20261109_counterparty_reconciliation.sql',import.meta.url),'utf8'));
  await assert.rejects(apply(edit),/denied/);
  await db.exec("select set_config('test.permitted','yes',false)");
  await apply(edit);
  await apply(edit);
  assert.equal((await db.query('select count(*)::int n from briskers.vendors')).rows[0].n,1);
  const deactivated = {...edit,name:'Changed fixture',active:false};
  await apply(deactivated,edit);
  await apply(deactivated,edit);
  await assert.rejects(apply({...edit,name:'Conflicting edit'}, edit),/requires review/);
  await assert.rejects(apply({...deactivated,id:shop}),/another payee/);
  await assert.rejects(apply({...edit,name:'Other business'},edit,id),/unavailable/);
  assert.deepEqual((await db.query('select name,active from briskers.vendors')).rows,[{name:'Changed fixture',active:false}]);
  console.log('Payee create, edit, deactivate, replay, permission and conflict checks passed.');
} finally { await db.close(); }
