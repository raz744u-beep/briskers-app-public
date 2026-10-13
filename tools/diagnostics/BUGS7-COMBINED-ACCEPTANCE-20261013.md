# Bugs 7 combined acceptance gate

This candidate combines editable/colored/reorderable Standard Notes, guarded
test-job cleanup, and finding synchronization repairs. Build and distribute only
the final combined candidate from PR #92 after its Android, diagnostics, and iOS
checks pass. Keep the PR unmerged until phone acceptance is complete.

## Data protection

- Keep the original phone in Force Offline until its pending operations have
  been reviewed and reconciled. Do not use it for Auto-mode acceptance yet.
- Keep Test 06 paused. Do not uninstall the app, clear its storage, or reset its
  cache to work around a failed check.
- Protect real jobs J7, J11, J12; invoices 6331, 6332, 6334; estimate 1997;
  all customer/vehicle records; and paid expenses and other real financial data.
- A successful cleanup preview is not permission to delete. Server cleanup
  starts disabled. Its separate rollout gate may only be enabled after every
  participating device is on a verified safe version and its offline work has
  been reviewed. Permanent deletion still needs the exact on-screen test-record
  confirmation for that particular job.
- Existing ordinary deletion RPCs preserve estimates and are not substitutes
  for comprehensive test cleanup.

## Automated evidence required

1. UI-action audit, Flutter analysis, and the entire Flutter test suite on the
   final source commit; diagnostic IDs must remain unique.
2. All 26 isolated in-app functional scenarios, including note presentation,
   cleanup permission/preview guards, and pending finding reconciliation.
3. Synthetic SQL tests for note permissions, versions, names and General-last
   behavior; and for cleanup dependencies, protected records, stale previews,
   atomic rollback, permissions, audit, tombstones and stale replay protection.
4. Behavioral client tests covering interrupted responses, database restart,
   concurrent edits, out-of-order finding metadata, pending photos, cleanup
   tombstone timing, and ordinary permission revocation.
5. Verify the final APK's package, version/build number, ZIP integrity and
   permanent signing-certificate fingerprint before distributing it.

Synthetic SQL tests do not establish real multi-session PostgreSQL race behavior
or Android background-isolate behavior. These remain separate review/acceptance
items; a test that was blocked must not be reported as passed.

## Phone acceptance, using the safe second phone

Use a backed-up, explicitly designated test fixture wherever a step writes data.
Do not delete real shop records or change payments to exercise a test.

1. Install the combined APK as an update. Confirm About shows its exact build.
2. Open Standard Notes. Verify the saved colors, edit controls for Owner only,
   drag ordering, and General remaining last. Cancel and reopen the editor.
3. On a test template, check an offline edit and reorder, app restart, then a
   controlled online reconciliation. Confirm a second device's newer edit is
   preserved or produces a recoverable conflict rather than being overwritten.
4. Open J12 read-only and compare finding count, text, photos and repair state
   with the server/other safe device. Do not manufacture a real finding edit to
   test the queue. Exercise write/retry scenarios only with the designated test
   fixture after its pending state has been reviewed.
5. As Owner, open Delete Test Jobs and use PREVIEW only. Check linked documents,
   dependency counts and lock reasons. Verify protected jobs stay locked and
   non-Owners cannot enter or perform cleanup. Offline local preview must remain
   available without asking the original phone to synchronize.
6. Recheck existing invoice/estimate notes, memo, warranty, payment balance and
   no-duplicate replay behavior; expense camera/gallery/manual receipt flows;
   invoice-to-expense navigation; numeric field selection; Jobs sort/pagination;
   and the separate Mark Job Completed prompt. Preserve real record values.

Record the tested device, APK build, connection mode and any failed step. Release
claims must distinguish automated passes, backend installation, and phone checks
that have actually been performed.
