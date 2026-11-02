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
- Job bootstrap and incremental server bundles now skip local purge tombstones **before modifying children**. Document index replace/upsert also skips deleted document IDs and documents whose Job is tombstoned. Synthetic tests cover both paths and unrelated business isolation.
- The existing Jobs list is subscribed to local-purge events to remove matching Job rows and search hits immediately, followed by a local-first refresh. Navigation and unrelated screens are unchanged.
- A paid-status Job, issued/closed invoice, converted estimate or unknown linked document kind blocks the incomplete local graph deletion rather than relying on an empty local payment cache.
- Synthetic payment erasure is forcibly disabled in release mode, even if someone supplies a synthetic build flag.
- Verified application code at `a7a5aa4c46d78b2c14bcd9c5e9b46f3786f91cf8`:
  diagnostics passed 254 tests, 1 skipped; the separate synthetic payment run
  passed 24 tests, 1 skipped. These suites overlap and must not be summed.
  The opposite-mode safety test is intentionally skipped in each configuration.
  Flutter analysis, Android release Kotlin compilation, and iOS compilation passed.

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

## Owner Delete 3 continuation

- Added platform-protected Owner enrollment: fresh authenticated user and business
  membership verification, device fingerprint/passcode challenge, account/session
  binding, seven-day offline enrollment, two-minute action grants, and synchronous
  grant invalidation on sign-out or account switch. Backgrounding locks idle grants.
- Role-map injection is now a unit-test-only constructor that refuses release mode.
  The production graph constructor accepts an unforgeable in-process Owner grant;
  it checks that grant before and after preview and throughout confirmation.
- Added native Android FragmentActivity/biometric configuration and iOS Face ID
  description without changing app identifiers, signing, navigation or database name.
  Secure enrollment is excluded from Android backup; other backup settings remain.
- Added an identity-only deletion journal in the same local transaction as record
  deletion and tombstones. It retains the author and original operation ID across
  restart, with state `awaiting_backend`. It does not claim successful remote sync.
- The regular Delete Job button is still **not wired to the new engine**. Enrollment
  UI, complete production graph coverage and verified reconciliation remain gates.
- Read-only inspection confirmed the production project has none of the four v3
  preview/execute/status/feed endpoints. The sandbox local-registration endpoint
  explicitly supports only `unpublished-local-job` and rejects remote identities.
  It must not be reused as synchronization for previously synchronized jobs.
- No backend changes or real shop-data tests were performed. The earlier corrected
  installer preflight is conditional, sandbox-scoped, and does not establish safe
  production deployment or full two-device acceptance.

## Reproducible evidence and remaining implementation

Application-code checks for `a7a5aa4c46d78b2c14bcd9c5e9b46f3786f91cf8`:

- [Diagnostics and synthetic-payment tests](https://github.com/raz744u-beep/briskers-app-public/actions/runs/41377441655).
- [Android release Kotlin compilation](https://github.com/raz744u-beep/briskers-app-public/actions/runs/41377441614).
- [iOS compilation](https://github.com/raz744u-beep/briskers-app-public/actions/runs/41377441573).

The recovered private corrected installer matches SHA-256
`5550d232dbce31a611dd170403a2e5b3680b7bcc375eda1cd7351a210350e509`.
`tools/owner_delete/verify_private_backend.mjs` provides a repeatable local
emulator check without publishing the private source. Its five synthetic suites
cover execution/rollback/retry/number fences, graph inventory, unpublished local
cancellation, storage state transitions, and scoped tombstone feeds. Auth and
Storage are emulated; this is not hosted or two-device acceptance.

Read-only function comparison found a newer private-bucket witness check in the
sandbox's storage inspection function. Preserve it. The archived installer is
bound to an empty sandbox, refuses an existing v3 installation, and is not a
production upgrade script.

Release remains blocked by unfinished engineering, not by a request for the
owner to repeat permission or supply the old source again:

1. The protected Owner enrollment service still needs its regular-app user flow.
2. The graph adapter still refuses financial/outbox relationships it cannot
   safely reconcile. A protected-record correction/archive route is not complete.
3. The journal is durable but has no active server consumer. The existing server
   cancellation protocol covers unpublished jobs only. Server-issued v3 consent
   expires after 24 hours; it cannot be silently renewed for an offline deletion
   of a changed synchronized graph. This requires explicit reconciliation and
   conflict handling before the regular Delete Job action is connected.
4. A current-schema production migration, real-provider storage checks, and
   multi-device resurrection tests remain unverified. Production has no v3
   preview/execute/status/feed endpoints.
5. No APK has been packaged or published for this continuation. Signing-certificate
   comparison, version/package verification, upgrade-with-data retention, and
   Samsung acceptance therefore remain outstanding.

Do not describe the compile workflow as an APK build, or this branch as a
completed feature/release candidate. Keep the production feature disabled and
the PR in draft until these gaps are resolved.
