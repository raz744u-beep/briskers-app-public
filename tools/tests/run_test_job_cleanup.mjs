// Isolated in-memory PostgreSQL/WASM; never opens a remote database connection.
// Pin @electric-sql/pglite to 0.3.14. See README_cleanup.md for setup/run details.
import {readFileSync} from 'node:fs';
import {resolve, dirname} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const moduleName=process.env.PGLITE_MODULE
  ? pathToFileURL(resolve(process.env.PGLITE_MODULE)).href : '@electric-sql/pglite';
const {PGlite}=await import(moduleName);
const db=new PGlite();
const files=[
  'tools/tests/test_job_cleanup_schema.sql',
  'supabase/migrations/20261013001224_owner_test_job_cleanup_v1.sql',
  'tools/tests/test_job_cleanup_cases.sql',
  'tools/tests/test_job_cleanup_isolation.sql',
  'tools/tests/test_job_cleanup_registry_cases.sql',
];
try {
  for (const file of files) {
    // Native CI opens a new psql session for each file. Do not let auth/settings
    // from the fixture leak into later stages and mask missing test setup.
    await db.exec('RESET ALL; RESET ROLE;');
    const results=await db.exec(readFileSync(resolve(root,file),'utf8'));
    console.log(`PASS ${file}: ${results.length} SQL statements`);
  }
  const count=await db.query('SELECT count(*)::integer AS passed_named_assertions FROM public.test_cleanup_assertion_results');
  console.log(JSON.stringify(count.rows[0]));
} catch(error) {
  console.error('FAIL',error.message,error.detail ?? '',error.where ?? '');
  process.exitCode=1;
} finally { await db.close(); }
