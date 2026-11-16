# Existing-record recovery

This change handles the existing Owner-numbered, quarantined recovery chain. It
never creates or submits a customer, vehicle, Job, invoice, visit, or payment.
The source and tests contain synthetic examples only.

The Owner opens Settings > Local Sync Status > Review and reconcile recovered
records, with Force Offline enabled, and selects Verify and reconcile existing
records. An existing authenticated Owner session is required. The explicit lookup
is the sole network exception: its fixed server RPC is STABLE, read-only, checks
Owner membership, and is not executable by anonymous callers. Ordinary uploads
stay disabled. Missing, ambiguous, or changed proof leaves the local hold intact.

A single SQLite transaction remaps exact relational identities, retains the
original snapshots and operation payloads in a recovery journal, saves the usable
invoice snapshot in SQLite, and marks the four original operations reconciled.
The operations are not deleted. A database trigger prevents their state from
being reset to a replayable state. The initial visit is matched too. Prior alias
records remain intact and no longer hide the adopted invoice. Cache reads and
writes use the transactional snapshot after adoption; old preference copies
cannot resurrect the original invoice or double-count its receipt.

The success message leaves Force Offline enabled. The Owner can reopen the
invoice from the list, verify the original total/payment/balance, then select
Auto to resume ordinary synchronization. A successful build is not proof that a
particular phone has completed reconciliation. No uninstall or data clearing is
part of this procedure.

Safety boundaries: unexpected linked queued edits, cached primary-key collisions,
changed invoice lines, additional visits, retirement, missing original records,
or a connection-mode transition fail closed. No existing row is merged away to
resolve a collision. Such a refusal requires diagnosis while preserving the hold.

Validation performed before release submission:
- 1,235 Flutter tests passed; the dedicated recovery suite passed 21 scenarios.
- Flutter analysis reported no issues.
- UI action audit passed, along with 39 candidate-gate and 10 signing-verifier tests.
- Hosted read-only transaction tests passed for Owner lookup, repeated lookup,
  initial-visit proof, missing operation rejection, non-Owner rejection, and
  anonymous execute denial. No business records were written by these tests.
- Failure at the local journal commit boundary rolls back identities, outbox
  state, and cache together; the database is reopened to verify durable rollback.

Release still requires exact-commit GitHub checks, the existing permanent
certificate, package com.briskers.briskers_app, and APK verification output.
Backend source: owner_recovery_lookup_v1.sql. Verification harness:
verify_owner_recovery_lookup.sql (runtime private inputs are never committed).
