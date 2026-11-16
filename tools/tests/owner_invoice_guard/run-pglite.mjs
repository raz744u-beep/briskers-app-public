// Optional in-memory Postgres/WASM verification. Requires @electric-sql/pglite
// installed separately; the psql runner is the standard CI path.
import { pathToFileURL } from 'node:url';
import { execFileSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
const modulePath = process.env.PGLITE_MODULE_PATH;
const { PGlite } = modulePath
  ? await import(pathToFileURL(modulePath).href)
  : await import('@electric-sql/pglite');
const notices = [];
const db = new PGlite();
try {
  const sql = execFileSync('python3', [join(dirname(fileURLToPath(import.meta.url)), 'assemble.py')], { encoding: 'utf8' });
  const version = await db.query('select version()');
  console.log(version.rows[0].version);
  await db.exec(sql, { onNotice: (notice) => notices.push(notice.message) });
  console.log(notices.join('\n'));
  const count = notices.filter((message) => message.startsWith('PASS:')).length;
  if (count !== 72) throw new Error(`Unexpected assertion count: ${count}`);
  console.log(`Passed ${count} isolated SQL assertions. Fixture transaction rolled back.`);
} catch (error) {
  console.error(notices.join('\n'));
  console.error({ message: error.message, code: error.code, detail: error.detail, where: error.where });
  process.exitCode = 1;
} finally {
  await db.close();
}
