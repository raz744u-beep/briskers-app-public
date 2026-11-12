# Bugs 35 local-first closeout follow-up

Continues installed 0.10.9 (4635), source f5d313a54f5a9a93997b08d176330c9ace0ec7f2, on the existing PR #447 release branch. Tracking issue #454.

## Included

- Owner individual/bulk invoice close commits a separate local lifecycle decision and index update atomically. Closed is immediately visible, excluded from close eligibility, survives restart, and overrides stale server detail/index responses. Closing never creates a payment or finalization intent. Explicit confirmed Owner reopening supersedes the closure.
- Background closure uses the existing idempotent endpoint with an immutable EMPTY receipt set. Its transactional payment-set check prevents the legacy close RPC from posting pending receipts. Original payment/finalization operations remain untouched. Failed closure sync backs off at least one minute; it does not reverse local Closed.
- Finalization always saves an existing durable intent before network work, including while online. Pending/inflight/review and already-confirmed matching receipts disable repeat submission and show their actual state. Later distinct receipts remain eligible after the prior operation is confirmed.
- Invoice cards use cached local paid/pending amounts and saved service descriptions without delaying first local paint. Generic Invoice / Invoice-number titles no longer replace saved labor descriptions.
- Job financial summaries accept recorded_pending and Closed independently of operational status. Previously recorded_pending was calculated but rejected by the local summary writer. Customer payment never marks mechanic wages Paid.
- Completed tasks offer an explicit Complete job action using the existing durable local status/outbox path. Job completion is not fabricated from payment or the historical task-display cutoff. Both online/offline completion confirmations now persist locally first.
- One task navigation control on Job Details, while preserving the main mechanic editor. Green Estimate/Invoice tile, normalized compact status colors, explicit historical-wage reconciliation labels. Whole-card taps and long-press actions retained.
- Existing Mark All Done, November 8 historical cutoff, assignment/hour edits, payroll duplicate protection, Cintas recurrence, receipt photos and VIN wording remain in the consolidated source.

## Verification

- New real SQLite tests: single and bulk offline close, duplicate retries, restart, stale server saves, atomic rollback for an ineligible selection, original pending finalization preservation, explicit reopen/re-close, and independent financial/operational states.
- Real DocumentsScreen test: three paid fixture invoices with saved labor descriptions; close one in Force Offline, immediately observe Closed, two remaining close candidates, and unchanged payment history. The rendered compact cards were inspected at phone dimensions.
- Isolated PostgreSQL endpoint test: empty-receipt close replay preserves all transaction/allocation/pending-payment rows. No production data was edited for testing.
- Existing recovery, fast local navigation, historical payroll, receipt/Cintas and financial-preservation regressions remain release gates. Android/iOS checks and signed upgrade verification are required for the exact release commit.
- Existing signed workflow is enabled by push on this branch and workflow_dispatch. Version code must exceed 4635; install-over verification now uses signed build 4635 as the intermediate baseline. Package and signing configuration are unchanged.

## Physical-device checks and limits

The Owner phone database is not available to these tests. Rick #6368 ($521.31), Gloria #6359 ($7,882.11), and Reginald #6357 are represented by synthetic fixtures; Reginald's fixture amount is not asserted to be his real payment amount. Confirm those actual records and the 19-invoice total on the phone, without re-entering payments.

For J-49/J-38, if their saved operational status was never explicitly completed, confirm Complete job once. Done tasks, invoice Paid/Closed, and mechanic wages remain deliberately independent. No customer-specific IDs or forced historical payment/status migration is embedded.

An invoice lacking saved verifiable financial details remains held for review rather than being closed from a display hint. Background closure can wait for separately authorized finalization; this does not prevent local closeout. Confirm eventual synchronization and restart behavior on the Owner phone.

Carry-forward limitations from 4635 remain: historical assignment notes are local recordkeeping; legacy server recurring-scheduler retirement requires separate reconciliation. This release does not delete or rewrite historical expenses, payroll, payments or photos.
