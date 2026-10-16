# Owner-only invoice guard: public synthetic tests

Status: **prepared source only; not deployed**. No hosted database mutations or
payment operations were performed for this work.

## Production migration

`supabase/migrations/20261014064717_owner_invoice_finalization_guard.sql` adds a
fail-closed, business-scoped Owner check before the existing `payments.create`
check in the finalization and closeout RPCs. It uses `auth.uid()` and
`briskers.is_owner(p_business_id) IS DISTINCT FROM true`; a missing user or
non-true owner result raises SQLSTATE `42501`, `Owner access required`.

The checked-in production migration remains unchanged from its reviewed form.
Its exact live-source SHA-256 allowlist is retained. It preserves the rest of
each function body and all function metadata, ACL, ownership, identity, settings
and comments. It refuses unexpected source or metadata and is atomic and
idempotent. Deploying it requires separate approval and a fresh read-only review
of the existing owner helper. This repository is not a live-schema baseline.

## Public fixture scope

`synthetic_rpcs.sql` contains independently authored **test-only** functions.
They check a fake permission, increment a write-attempt probe, write one row to
a synthetic log, and optionally return an input UUID. They contain no live
application RPC implementation, financial calculations, ledger operations,
invoice lifecycle, or copied production function bodies. The role helper uses
an independently named synthetic role-binding table.

`assemble.py` loads these public fixtures and computes their original and
guarded SHA-256 fingerprints. It substitutes **only those fingerprint literals
in an in-memory copy** of the migration for this synthetic test transaction.
It never edits the production migration or weakens its checked-in allowlist.
The generated stream is test input only, not a deployable migration; do not
save or publish assembled test output as an application schema.

The public suite checks:

- Owner access and preservation of synthetic return values, logged identity,
  null-entity behavior and repeated calls across both target signatures.
- Office, manager, mechanic, inactive owner, unknown user, unauthenticated,
  cross-business owner and null-business rejection before the old permission
  check or synthetic body runs.
- No denied writes or write attempts. Sequence probes survive exception
  rollback, so rolled-back table writes cannot hide a failure.
- A null owner-helper result fails closed; a null user is rejected even if a
  synthetic helper returns true; an owner still needs `payments.create`.
- Exact fixture body preservation apart from the inserted check, unchanged
  ACL/OID/owner/settings/comments, a no-op second run, and atomic rejection of
  drift, duplicate guards, altered metadata and missing targets/dependencies.

This is **72 synthetic SQL assertions**. These are narrower than a separate
prior private validation of **84 assertions** using exact application bodies.
That older input, checkout and evidence are retained only in a private local
copy and are not included here. The 84-check result must not be attributed to
this public CI suite. The public suite cannot establish equivalence of actual
financial behavior, real payment helpers, locks/concurrency, RLS, Supabase Auth,
or PostgREST. Those require separately authorized private validation.

## Standalone PostgreSQL run

Use a dedicated disposable local PostgreSQL cluster and database
`briskers_owner_guard_synthetic`. Do not use a tunnel to a live server. No hosted
secrets are needed. Installation refuses any database containing `auth`,
`briskers`, or `owner_guard_test`; the complete fixture transaction rolls back.

```sh
ACK_SYNTHETIC_POSTGRES=1 PGPASSWORD=synthetic-test-only \
  tools/tests/owner_invoice_guard/run.sh
```

Requires Python 3, `psql`, and PostgreSQL 15 or later. Optional loopback connection
settings are `OWNER_GUARD_PGHOST`, `OWNER_GUARD_PGPORT`, and
`OWNER_GUARD_PGUSER`, defaulting to `127.0.0.1`, `5432`, and `postgres`.
Generic libpq host/service/database overrides are ignored.

### GitHub Actions integration snippet

This source change does not edit or dispatch a workflow itself.

```yaml
owner-payment-guard:
  runs-on: ubuntu-latest
  timeout-minutes: 10
  services:
    postgres:
      image: postgres:17
      env:
        POSTGRES_USER: postgres
        POSTGRES_PASSWORD: synthetic-test-only
        POSTGRES_DB: briskers_owner_guard_synthetic
      ports:
        - 5432:5432
      options: >-
        --health-cmd "pg_isready -U postgres -d briskers_owner_guard_synthetic"
        --health-interval 5s
        --health-timeout 5s
        --health-retries 10
  steps:
    - uses: actions/checkout@v4
    - name: Test owner-only guard with synthetic PostgreSQL fixtures
      env:
        ACK_SYNTHETIC_POSTGRES: '1'
        PGPASSWORD: synthetic-test-only
      run: tools/tests/owner_invoice_guard/run.sh
```

### Optional in-memory run

No app dependency is added. Install the test engine in a separate temporary
location:

```sh
npm install --prefix /tmp/briskers-owner-test-tools --save-exact @electric-sql/pglite@0.5.9
PGLITE_MODULE_PATH=/tmp/briskers-owner-test-tools/node_modules/@electric-sql/pglite/dist/index.js \
  node tools/tests/owner_invoice_guard/run-pglite.mjs
```

Local verification on 2026-10-14 passed 72 public synthetic assertions on
PGlite 0.5.9 (PostgreSQL 18.6/WASM). Native `psql`/Postgres/Docker were unavailable;
the native service runner and GitHub service job were prepared but not run here.

References: [PostgreSQL CREATE FUNCTION](https://www.postgresql.org/docs/current/sql-createfunction.html),
[Supabase auth.uid and RLS](https://supabase.com/docs/guides/database/postgres/row-level-security).
