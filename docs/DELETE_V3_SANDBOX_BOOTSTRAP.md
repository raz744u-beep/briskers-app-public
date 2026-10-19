# Owner Delete v3 — synthetic sandbox bootstrap preflight

**Scope:** client engineering handoff for #116 / draft #236. This is not a
production migration, a server deployment, or permission to erase real records.
The private backend SQL, authentication credentials and deployment evidence must
stay outside this public application repository.

## Root cause confirmed Oct 18, 2026

A new Supabase development branch with `with_data=false` failed during
historical migration replay. The first recorded migration is
`20260923000535_performance_indexes_v001`. Its assumptions include an
already-created `briskers.appointment_requests` table. The branch had no
`briskers` schema, no completed migrations, and logged
`schema "briskers" does not exist`.

The migration record describes **incremental changes**, not a complete base
installation. The old branch was deleted; subsequent branch listing showed
only the existing main branch. No production rows or SQL were changed.

## Required sequence BEFORE another paid branch

1. Obtain the reviewed **private, schema-only foundation** for the matching
   Briskers schema revision, independently of the existing incremental
   migrations. It must include the schema, core tables, foreign keys, indexes,
   triggers, callable functions, RLS policies and required role setup, without
   any business, customer, invoice, payment, membership or imported data.
2. Review SQL and migration ordering privately. Do **not** insert an old baseline
   into live Supabase migration history just to make a branch appear healthy.
   A plain schema-only snapshot of current production is *not automatically*
   a valid precursor to historical migrations; replay may fail on duplicates.
   Prove the foundation + incremental replay strategy offline or on a permitted
   isolated resource first.
3. For an available private SQL candidate, run the **local static screen**:
   `python3 tools/tests/owner_delete_sandbox_preflight.py /private/path/foundation.sql`.
   It checks for core declarations and obvious business-data DML; it does not
   execute SQL, connect to Supabase, prove schema parity, or authorize deployment.
4. Obtain **fresh** branch cost confirmation within the Owner's cumulative
   $1 budget, create one no-data disposable branch only after readiness, and
   confirm actual table/function/trigger/policy parity and zero business rows.
   Keep cleanup monitoring and delete the branch if migrations fail or testing
   finishes. Do not infer the earlier temporary environment is still usable.
5. Only after normal sandbox bootstrap and a separately authorized permission
   resolution, install/review private owner-deletion-3.0 on that synthetic
   environment. Test Owner vs non-Owner RLS; exact linked-record preview;
   synthetic finalized/pending payments and full financial-report removal;
   external settlement refusal; concurrent payment/delete conflicts; partial
   failures, number reuse exactly once; attachment/storage cleanup; and stale
   offline upload from another device. Capture receipts and rollback evidence.

## Explicit restrictions

The earlier synthetic permission continuation was restricted to
**user-controlled manual execution** after tool execution was denied. Do not
bypass that restriction through another tool, connected account, agent, or a
new sandbox. New branch/project funding is **not** approval to run that SQL.
The old manual SQL is bound to another project's identity and must not be
repurposed.

No production delete, protected job J-19, or invoice #6346 is a test fixture.
The client stays behind its missing-server safety gate until all hosted,
offline, Storage, accounting, Android and iOS acceptance checks pass.

## Preflight interpretation

A static preflight PASS means only that certain object declarations appear in
the private SQL and it does not obviously load business data. SQL might still
contain unsafe dynamic statements, lack valid RLS or triggers, or fail to replay.
A preflight FAIL must halt any attempt to create a paid branch for that candidate.
