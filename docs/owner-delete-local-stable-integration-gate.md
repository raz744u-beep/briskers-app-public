# Owner Delete Job — stable integration gate (2026-11-01)

Source prototype: PR #367, branch `feat/oct28-owner-delete-v3-current-main`.

This is an integration branch based on current `main`. It is **not** approved
for production installation or deletion of actual shop records yet.

## Integration implementation status (November 1)
- Current stable main is the base; its navigation and shell files have not been replaced.
- Payment confirmation UI and five formatting regression tests are staged.
- `LocalJobDeletionV3` tombstone/cleanup engine and `LocalJobGraphDelete` local graph implementation are staged as **unwired source**.
- The staged graph service denies Owner access by default: no secure enrollment/provider is wired on stable, and live Job actions never call it. Production financial/outbox references fail closed instead of being erased.
- Unit tests cover local atomic removal/markers, scope and role rejection, revision/preview race rollback, unrelated record preservation, pending payment protection and queued edit refusal.
- Synthetic-only payment and audit erasure remains isolated by the `BRISKERS_SYNTHETIC_BUILD` build flag and is **not enabled in the regular app**.
- No changes to production data, production network deletion, app signing identity, package ID or Android navigation.

## Confirmed Android TEST behavior
- A locally stored synchronized sample Job TEST-7001 and its sample Invoice
  TEST-8001 were removed immediately in the isolated TEST application.
- The synthetic TEST-7003 Job, TEST-8003 Invoice, FAKE $200 cash receipt and
  FAKE payment-edit audit were removed immediately in the isolated TEST build.
- Neither test establishes the behavior of production payment tables or real
  payment-edit audit records. Real card and bank transactions are not reversed.
- Preview formatting of synthetic payments was corrected on the TEST branch,
  with regression tests in `test/offline_job_purge_dialog_test.dart`.

## Do not copy into stable
- `synthetic_local_owner_fixture.dart`, TEST fake payment erasure exemption,
  TEST flags, package identities, or sandbox publishable-key configuration.
- The old server Delete Job RPC path and the Supabase deletion feed.
- A password setup that grants Owner privilege from an arbitrary local cache
  without a secure device/account enrollment process.

## Required before stable merge
1. Preserve the current main branch's colorful/scrollable navigation and all
   main branch bug fixes; do not overwrite the complete Job screen from PR #367.
2. Reconcile real payment, payment-edit-audit, invoice detail, customer,
   vehicle, expense, payroll and media relationships. An Owner-approved
   deletion must be one local transaction, with unrelated data untouched.
3. Commit durable deletion markers at the same instant as local deletion,
   and make pull/replay ignore deleted identities until reconciliation is
   implemented. Do not activate unfinished server sync.
4. Require locally authenticated Owner for the exact business; enforce at
   both preview and commit. Preserve existing local phone database on upgrade.
5. Verify after delete that Job and linked records disappear immediately
   from Job/Invoice lists, detail cache, customer service history and counts.
6. Run financial/rollback/idempotency and after-restart tests using **synthetic
   records only**, then test an installable staging APK on Samsung.
7. Merge into stable only after the above checks pass and user approves.

The target design is Owner-controlled, local-first, network-independent
deletion. Prior synchronization must not by itself disqualify deletion.
