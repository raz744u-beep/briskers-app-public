# Guarded test Job cleanup: review and isolated tests

## Scope and deployment state

The migration `supabase/migrations/20261013001224_owner_test_job_cleanup_v1.sql` is prepared for review only. It has not been applied to Supabase. No production deletion RPC was called. No records are approved for cleanup by this implementation; the owner must select a Job, review its current dependencies, and type its exact `DELETE TEST <job_number>` confirmation at action time.

The migration leaves the business rollout gate disabled. Its final comments contain the exact, separate administrator enable transaction using supplied `business_id` and `owner_user_id` psql variables. First verify every active/offline device uses the tombstone-aware client and reconcile its pending work/media. Enable only after explicit review/approval. The private gate change audit records every enable, disable, and removal; clients have no gate-write endpoint.

J-7, J-11, J-12, invoices 6331/6332/6334 and estimate 1997 are always blocked by normalized number. Deployment also captures their current identities so renumbering cannot evade protection. There is no inferred permission for other Job numbers.

## API

- `briskers_test_job_cleanup_preview_v1(p_business_id uuid, p_job_id uuid)` returns schema_version, business_id, job_id, job_number, rollout_enabled, can_delete, blocked_reasons, documents, dependencies, fingerprint. Read-only, owner-only.
- `briskers_test_job_cleanup_execute_v1(p_business_id uuid, p_job_id uuid, p_expected_fingerprint text, p_test_confirmation text)` rechecks authorization, gate, schema, dependencies and exact confirmation under locks. Returns schema_version, business_id, job_id, deleted_job_id, deleted_document_ids and audit_id. Only matching fresh preview is accepted.
- `briskers_test_job_cleanup_tombstones_v1(p_business_id uuid)` returns schema_version, business_id, deleted_job_ids and deleted_document_ids. Current business members, including mechanics, receive only permanent deleted UUIDs; no audit or document content is exposed. The client must distinguish cleanup from ordinary access revocation and preserve dirty local work for review.

Only draft, unnumbered, native invoices/estimates with no publication/payment/authorization/import/conversion provenance qualify. Estimates belonging to the target are removed, never detached and preserved. All conversion links, external references, appointments, media, real service history, financial history, operation ledgers and unknown dependencies block. Only owned draft lines, unsigned disclaimers and initial empty visit/status rows are removable. Customers, vehicles, unrelated documents and financial records remain. Numbers are not reused.

The scanner searches UUID references case-insensitively and with hyphens normalized in every `briskers` base table (including JSON/soft references), and external-schema tables with FKs to removable tables. It blocks unknown matching dependencies and pins removable table columns/types/nullability/generated attributes plus FK/primary/unique constraints. Arbitrary soft references outside `briskers` without an FK cannot be discovered; deployment must not claim coverage of an unreviewed external system.

## Security and compatibility

- Three public RPC EXECUTE grants to `authenticated`, with explicit server owner checks for preview/execute and membership check for UUID-only tombstone read. EXECUTE revoked from PUBLIC/anon.
- New private schema has no PUBLIC/anon/authenticated usage, table or helper-function grants. All private tables have RLS enabled with no client policies. No existing user role is elevated and no token/credential is created.
- New INSERT/identity-key UPDATE triggers on jobs/documents use a private unique identity registry UPSERT. Reusing a deleted identity fails; stale repeatable-read snapshots serialize or fail instead of resurrecting data. Ordinary field updates do not touch this registry. Reassigning an already-registered identity to another business fails intentionally.
- Only destructive execute requires READ COMMITTED. Normal writes at other isolation levels are not rejected merely for isolation choice.
- Execute takes `SHARE ROW EXCLUSIVE` locks in deterministic order on all `briskers`, private cleanup, and directly FK-referencing external tables. This briefly blocks writes across businesses, while ordinary reads continue. This is an infrequent owner administrative operation, not a high-throughput API.
- Disabled rollout is rejected before locking. Lock acquisition has a 3-second timeout. Execute requires a pre-existing finite statement timeout of at most 15 seconds; current authenticated/authenticator roles were verified at 8 seconds. Changing statement_timeout inside an active RPC is not presented as an effective timer. Failed locks, timeouts, constraints, stale previews or late errors roll back all deletion/audit/tombstone changes.
- Existing owner-triggered activity capture returns without adding employee audit rows. Existing Job/visit deletion triggers append only retained job-sync events. The dedicated audit always records an actual successful cleanup; a late injected failure verifies complete rollback.
- Read-only metadata verification is not a production deployment test. Run security advisors and review the exact artifact before any authorized deployment. Do not enable the gate merely because migration application succeeds.

## Reproducible functional tests (no remote database)

Requires Node and exactly `@electric-sql/pglite@0.3.14`. Install it in a disposable directory if it is not already available:

```sh
npm install --prefix /tmp/briskers-cleanup-test --save-exact @electric-sql/pglite@0.3.14
PGLITE_MODULE=/tmp/briskers-cleanup-test/node_modules/@electric-sql/pglite/dist/index.js \
  node tools/tests/run_test_job_cleanup.mjs
```

The runner creates a fresh in-memory PostgreSQL/WASM instance and loads the synthetic schema, migration, functional cases, separate isolation cases and ordinary-write/real-role registry cases. It has no database URL or network connection. It prints SQL statement counts separately from the actual named assertion count. Exception-based guard tests additionally fail if an expected rejection does not occur.

The schema fixture contains synthetic IDs/names only. Its columns/defaults/generated expressions and FK/unique/primary-key shape were verified against the current schema on 2026-10-13. It intentionally omits unrelated CHECK constraints and business triggers; the fixture is not a full Supabase clone. Never load it into an existing or remote database.

## Isolated native CI job

`.github/workflows/diagnostics.yml` now includes `cleanup-postgres`, using the official exact-version `postgres:17.11-bookworm` service image and a six-minute job timeout. The existing GitHub permission remains `contents: read`. No repository/production secrets are supplied; the dummy database password is for the disposable service only. The service exposes no host port. `run_test_job_cleanup_native.sh` talks only through `docker exec` to the verified image and accepts no database URL.

The job creates two fresh synthetic databases in that service. It runs functional/isolation/ordinary-create/identity-update/real-role permission cases, measures a read-only preview over 2,000 unrelated 1KiB synthetic JSON payloads, checks that a 500ms outer request timeout rolls back cleanup, then runs both coordinated two-session races. The measurement is only a synthetic regression datapoint, never a production latency estimate. The broad locking remains a deployment tradeoff.

The native CI job is prepared, not yet run in this work session. Deployment remains held until the job passes on the exact reviewed commit. A successful migration or PGlite run is not a substitute for that native concurrency result. No local socket startup was retried.

## Concurrent tests for a permitted native environment

These two-session scripts are provided but NOT executed in the current sandbox. Native PostgreSQL 18.4 initialization succeeded in a disposable directory, but startup failed with: `could not create Unix socket ... Operation not permitted`. No alternate listener, escalation or further server-start attempt was used. PGlite is single-session and cannot establish real concurrent blocking behavior.

Use a brand-new disposable local PostgreSQL cluster where local sockets are explicitly permitted. Set LOCAL_TEST_DB to its verified local connection string. Never point these commands at Supabase or a shared database. Load only schema + migration + race setup, not functional cases (which delete their fixtures):

```sh
psql "$LOCAL_TEST_DB" -X -v ON_ERROR_STOP=1 \
  -f tools/tests/test_job_cleanup_schema.sql \
  -f supabase/migrations/20261013001224_owner_test_job_cleanup_v1.sql \
  -f tools/tests/test_job_cleanup_race_setup.sql
psql "$LOCAL_TEST_DB" -X -f tools/tests/test_job_cleanup_payment_race_a.sql & a=$!
psql "$LOCAL_TEST_DB" -X -f tools/tests/test_job_cleanup_payment_race_b.sql & b=$!
wait "$a"; a_status=$?; wait "$b"; b_status=$?
test "$a_status" = 0 && test "$b_status" = 0
psql "$LOCAL_TEST_DB" -X -f tools/tests/test_job_cleanup_snapshot_race_a.sql & a=$!
psql "$LOCAL_TEST_DB" -X -f tools/tests/test_job_cleanup_snapshot_race_b.sql & b=$!
wait "$a"; a_status=$?; wait "$b"; b_status=$?
test "$a_status" = 0 && test "$b_status" = 0
```

The payment race coordinates with advisory signals: preview occurs before another session inserts a pending payment, execute waits behind that write, and the post-lock preview must reject the changed fingerprint. The snapshot race establishes an old repeatable-read snapshot before deletion, then attempts to replay the deleted identity; the unique-registry guard must serialize or reject it. Signals have bounded waits. These scripts require native validation before claiming concurrency coverage.

Snapshot reasoning follows PostgreSQL's documented rule: a VOLATILE function gets a fresh snapshot for each nested query; the execute function invokes its STABLE preview in a separate query after acquiring write locks. The stable preview then sees one consistent post-lock snapshot. Documentation: https://www.postgresql.org/docs/current/xfunc-volatility.html
