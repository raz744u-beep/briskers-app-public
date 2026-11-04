import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PGlite } from '@electric-sql/pglite';

const db = new PGlite();
const uuid = (number) =>
  '00000000-0000-0000-0000-' + String(number).padStart(12, '0');
const [shop, other, owner, mechanicA, mechanicB, employeeA, employeeB, job, invoice, line] =
  Array.from({ length: 10 }, (_, index) => uuid(index + 1));
try {
  await db.exec(`
    create role anon;
    create role authenticated;
    create schema auth;
    create schema briskers;
    create function auth.uid() returns uuid language sql stable as $$
      select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
    $$;
    create table briskers.memberships(business_id uuid,user_id uuid,active boolean,role_code text);
    create table briskers.employees(business_id uuid,id uuid,user_id uuid,active boolean,compensation_enabled boolean,display_name text);
    create table briskers.job_assignments(business_id uuid,job_id uuid,employee_id uuid,active boolean);
    create table briskers.employee_compensation(id uuid,business_id uuid,employee_id uuid,effective_from date,hourly_rate numeric,payment_type text);
    create table briskers.jobs(id uuid,status text);
    create table briskers.sales_documents(business_id uuid,id uuid,job_id uuid,kind text,status text);
    create table briskers.sales_document_lines(business_id uuid,id uuid,document_id uuid,line_kind text,description text,name text);
    create function briskers.is_owner(b uuid) returns boolean language sql stable as $$
      select exists(select 1 from briskers.memberships
        where business_id=b and user_id=auth.uid() and active and role_code='owner')
    $$;
    insert into briskers.memberships values
      ('${shop}','${owner}',true,'owner'), ('${shop}','${mechanicA}',true,'mechanic'),
      ('${shop}','${mechanicB}',true,'mechanic');
    insert into briskers.employees values
      ('${shop}','${employeeA}','${mechanicA}',true,true,'Mechanic A'),
      ('${shop}','${employeeB}','${mechanicB}',true,true,'Mechanic B');
    insert into briskers.job_assignments values
      ('${shop}','${job}','${employeeA}',true), ('${shop}','${job}','${employeeB}',true);
    insert into briskers.employee_compensation values
      ('${uuid(11)}','${shop}','${employeeA}','2000-01-01',40,'hourly'),
      ('${uuid(12)}','${shop}','${employeeB}','2000-01-01',60,'hourly');
    insert into briskers.jobs values ('${job}','open');
    insert into briskers.sales_documents values ('${shop}','${invoice}','${job}','invoice','open');
    insert into briskers.sales_document_lines values ('${shop}','${line}','${invoice}','labor','Repair','Labor');
  `);
  await db.exec(readFileSync(new URL(
    '../../../supabase/migrations/20261104230000_payroll_reconciliation.sql',
    import.meta.url,
  ), 'utf8'));
  const call = async (name, args) => {
    const params = args.map((_, i) => '$' + (i + 1)).join(',');
    const result = await db.query(`select public.${name}(${params}) as value`, args);
    return result.rows[0].value;
  };
  const signIn = (user) => db.query("select set_config('request.jwt.claim.sub',$1,false)", [user]);
  const assign = (employee) => call('briskers_assign_payroll_labor', [shop, job, invoice, line, employee]);
  const list = (business = shop) => call('briskers_list_payroll_labor', [business, job]);
  const change = (id, revision, minutes, state) =>
    call('briskers_update_my_payroll_labor', [shop, job, id, revision, minutes, state]);
  const history = (employee) => call('briskers_payroll_payment_history', [shop, employee]);
  const pay = (employee, ids, date, amount) => call('briskers_record_shared_payroll',
    [shop, employee, ids, date, 'Cash', amount, '']);

  await assert.rejects(list(), /Active payroll assignment/);
  await signIn(owner);
  await assign(employeeA);
  await assign(employeeA);
  await assign(employeeB);
  const ownerRows = await list();
  assert.equal(ownerRows.length, 2);
  const a = ownerRows.find((row) => row.employee_id === employeeA);
  const b = ownerRows.find((row) => row.employee_id === employeeB);
  await signIn(mechanicA);
  const ownRows = await list();
  assert.deepEqual(ownRows.map((row) => row.id), [a.id]);
  assert.equal('rate_cents' in ownRows[0], false);
  await assert.rejects(list(other), /Active payroll assignment/);
  await assert.rejects(change(b.id, 0, 0, 'In Progress'), /Labor portion not available/);
  await assert.rejects(history(employeeA), /Owner payroll access/);
  await change(a.id, 0, 0, 'In Progress');
  await change(a.id, 1, 150, 'Done');
  await change(a.id, 1, 150, 'Done');

  await signIn(mechanicB);
  assert.deepEqual((await list()).map((row) => [row.id, row.state]), [[b.id, 'Open']]);
  await change(b.id, 0, 0, 'In Progress');
  await change(b.id, 1, 60, 'Done');

  await signIn(owner);
  const completed = (await list()).find((row) => row.id === a.id);
  await assert.rejects(pay(employeeA, [a.id], completed.completed_date, 1), /Payroll total/);
  const receipt = await pay(employeeA, [a.id], completed.completed_date, 10000);
  await signIn('');
  await signIn(owner);
  assert.deepEqual(await pay(employeeA, [a.id], completed.completed_date, 10000), receipt);
  await assert.rejects(pay(employeeA, [a.id], completed.completed_date, 999), /Conflicting payroll replay/);
  assert.equal((await history(employeeA)).length, 1);
  assert.deepEqual(await history(employeeB), []);
  assert.equal((await list()).find((row) => row.id === b.id).paid, 0);
  assert.equal((await db.query('select status from briskers.jobs')).rows[0].status, 'open');
  console.log('PASS: two mechanic identities, shared labor, Owner payment, exact retry, and shop isolation');
} finally {
  await db.close();
}
