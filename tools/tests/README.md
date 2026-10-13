# Isolated SQL regression tests

These tests use synthetic UUIDs, synthetic records, and an in-memory PostgreSQL
engine. They do not connect to Supabase or read or change any real business data.

## Standard note styling and versioned edits

Requirements: Node.js 20+ and pinned `@electric-sql/pglite@0.3.14`.

Install the test dependency in a disposable directory, then run from the repository:

```sh
mkdir -p /tmp/briskers-sql-tests
npm install --prefix /tmp/briskers-sql-tests @electric-sql/pglite@0.3.14
PGLITE_MODULE=/tmp/briskers-sql-tests/node_modules/@electric-sql/pglite/dist/index.js \
  node tools/tests/standard_note_styles_sql_test.mjs
```

The runner applies the migration twice to a synthetic legacy schema and checks
24 cases covering backward-compatible reads, default/persisted colors, General
ordering and rename protection, optimistic versions, field-level patches,
authorization and tenant boundaries, validation, ACLs, and preservation after
rejected writes. Any failure exits nonzero. Auth/permission functions are stubs;
this test does not replace live permission verification under real user accounts.

Verified locally on 2026-10-13: 24 checks passed. No live migration was applied by
this test. Flutter analysis and regression tests run separately in GitHub Actions.
