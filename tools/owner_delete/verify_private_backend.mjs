// Local emulator verification only. This script never connects to Supabase.
// Private source stays outside this public repository. No installer guard is
// modified, and these module tests are not hosted installation acceptance.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';

const source = process.argv[2];
if (!source) {
  console.error('Usage: node tools/owner_delete/verify_private_backend.mjs <extracted corrected archive>');
  process.exit(2);
}
const root = path.resolve(source);
const handoff = path.join(root, 'original/briskers-private-handoff-20261018');
const backend = path.join(handoff, 'backend');
const require = createRequire(path.join(backend, 'package.json'));
const {PGlite} = require('@electric-sql/pglite');
const {buildBody, root: bootstrapRoot} = await import(
  pathToFileURL(path.join(handoff, 'bootstrap/build.mjs')));
const sha = value => createHash('sha256').update(value).digest('hex');
const installer = fs.readFileSync(path.join(root,
  'deliverables/atomic_installer_CORRECTED_REVIEW_ONLY.sql'), 'utf8');
assert.equal(sha(installer), '5550d232dbce31a611dd170403a2e5b3680b7bcc375eda1cd7351a210350e509');
const baseline = buildBody().body;
const manifest = JSON.parse(fs.readFileSync(new URL('manifest.json', bootstrapRoot), 'utf8'));
assert.equal(sha(baseline), manifest.generated_body.sha256);
const start = installer.indexOf('-- START REVIEW-CORRECTED SOURCE 01_approved_core_patch_ONLY.sql');
assert.ok(start > 0);
const read = name => fs.readFileSync(path.join(backend, name), 'utf8');
const suites = ['execute_tests', 'graph_tests', 'local_cancellation_tests',
  'storage_tests', 'state_feed_tests'];
const results = [];
for (const suite of suites) {
  // No dataDir or network endpoint: every suite gets an empty in-memory DB.
  const db = new PGlite();
  try {
    await db.exec(`CREATE ROLE anon;CREATE ROLE authenticated;CREATE ROLE service_role;
      CREATE SCHEMA auth;CREATE TABLE auth.users(id uuid PRIMARY KEY);
      CREATE TABLE auth.sessions(id uuid PRIMARY KEY,user_id uuid NOT NULL REFERENCES auth.users(id),not_after timestamptz);
      CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
        SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
      CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$
        SELECT jsonb_build_object('sub',auth.uid(),'role','authenticated',
          'session_id',auth.uid(),'exp',floor(extract(epoch from now()+interval '1 hour'))::bigint) $$;
      CREATE SCHEMA storage;
      CREATE TABLE storage.objects(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        bucket_id text NOT NULL,name text NOT NULL,
        version text NOT NULL DEFAULT '00000000-0000-4000-8000-0000000000a1',
        updated_at timestamptz DEFAULT now(),UNIQUE(bucket_id,name));`);
    await db.exec(baseline);
    // Run only SQL modules and their ACL gate in the emulator. The physical
    // target and empty-host guards are intentionally NOT claimed as tested.
    await db.exec('BEGIN;\n' + installer.slice(start));
    await db.exec(`CREATE FUNCTION auth.test_session() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN INSERT INTO auth.sessions(id,user_id,not_after)
        VALUES(NEW.id,NEW.id,clock_timestamp()+interval '1 day');RETURN NEW;END$$;
      CREATE TRIGGER test_session AFTER INSERT ON auth.users
        FOR EACH ROW EXECUTE FUNCTION auth.test_session();`);
    if (suite !== 'state_feed_tests') {
      await db.exec(read('safety_tests.sql').split('DO $t$')[0]);
    }
    let testSql = read('v3/' + suite + '.sql');
    if (suite === 'graph_tests') {
      // The captured full baseline requires approved appointment requests.
      // Correct the old synthetic fixture; retain the production trigger.
      const fixture = "clock_timestamp(),'Synthetic appointment request') RETURNING id INTO req;";
      assert.equal(testSql.split(fixture).length, 2);
      testSql = testSql.replace(fixture, fixture +
        " UPDATE briskers.appointment_requests SET status='approved' WHERE id=req;");
    }
    await db.exec(testSql);
    results.push({suite, passed: true});
    console.log('PASS', suite);
  } catch (error) {
    results.push({suite, passed: false, error: error.message});
    console.error('FAIL', suite, error.message, error.where ?? '');
    process.exitCode = 1;
  } finally {
    await db.close();
  }
}
console.log(JSON.stringify({
  installer_sha256: sha(installer), baseline_sha256: sha(baseline), results,
  limits: ['Emulated Auth claims and sessions', 'Simulated Storage metadata only',
    'No hosted installer, real object deletion, concurrent devices, or production acceptance']
}, null, 2));
