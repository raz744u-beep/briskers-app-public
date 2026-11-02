# Durable Tasks / Payroll TEST milestone

This is a functional **isolated local workflow milestone**, not a production integration sign-off. Entry point: `lib/tasks_payroll_integrated_main.dart`. Package: `com.briskers.test.tasks_payroll_integrated_test`. Dedicated database: `briskers_integrated_payroll_TEST`. No internet permission in the delivered APK. No Supabase initialization or production outbox consumer. Production app, records, main, backend migrations and regular APK are untouched.

## Implemented

- Create local TEST jobs; add one or more invoice-style labor lines, each producing a service task; assign multiple TEST mechanics.
- Each mechanic starts work, edits actual hours, completes independently. One completed mechanic portion can be paid while another remains open. Job task counts/status derive from local state.
- Employee profile: Details, Tasks, Payroll, Reports, Taxes & 1099. Payroll selects completed unpaid portions for a Monday-based payroll week. Outside-week selections require an Owner reason.
- Integer-cents earnings from the existing durable `LocalMechanicWorkCreditRepository`, at snapshotted assignment rates (actual time rounds to the nearest minute; pay is computed from minutes); independent weekly base for the base-enabled TEST employee; signed hourly earnings adjustment requiring an Owner reason.
- Review and Verify Payment: method, date, gross, explicit advance repayment and net. Partial-job pay does not close work, jobs or invoices.
- One SQLite transaction validates selected work versions, writes immutable payment/work snapshots, marks credits paid, records a weekly base once, deducts repayment, writes audit, and enqueues a unique blocked TEST sync operation. Exact retries return the existing operation; conflicting or overlapping requests fail.
- Paid portions cannot reopen or change. Add a new labor/recheck line to represent additional work. Unpaid work can reopen, invalidating stale selections.
- File-backed persistence, local screen refresh after successful transactions, collapsed advances, historical payments in Reports, gross income separate from repayment.

## Incomplete / intentionally blocked

- The existing regular invoice editor, existing Job screens and existing employee records are **not wired into this milestone**. Local TEST jobs/labor/employees are created through the integration harness. This is beyond the old calculation demo but is not full regular-app integration.
- Local TEST Owner role is fixed; real device/PIN identity and mechanic session permissions are not integrated. Repository non-Owner guards are regression-tested, not proof of production authentication.
- Invoice document/customer creation, customer payment/final closure prompts, production tax/1099 export and editing employee details are not implemented here. The Taxes tab shows recorded gross only.
- The existing durable work-credit repository is reused; its `recordWork` method adds revision-checked time edits. No second synthetic credit ledger is used by this entry point.
- Sync delivery and financial posting remain disabled. Blocked TEST outbox rows exercise transaction persistence but do not claim verified server synchronization/idempotency.
- No physical Note 9 validation of this new APK has been claimed. CI validates API 29 emulator installation, launch, native SQLite persistence and reboot through an internal bounded on-device probe (no VM service required), provided all workflow steps pass.

The internal native acceptance entry point is `lib/payroll_native_acceptance_main.dart`. It is not the delivered APK. It creates a payment on first launch, validates immutable history and duplicate prevention, and requires the same records on the post-reboot launch. Host tests exercise both probe phases too.

## Manual Note 9 acceptance

1. Install **Briskers Integrated TEST** alongside the regular app. Keep the regular app offline as previously agreed. This APK uses different application storage and has no network permission.
2. Jobs / Tasks: New TEST job. Expand it and add labor, e.g. Repair, 2.50 hours. Use Assign mechanic to add Chris and Kam to the same task.
3. Start Chris, enter 2.50 actual hours, then Done. Leave Kam open. Job must show 0 of 1 done and In Progress.
4. Employee / Payroll: Chris > Payroll. Enter the Monday for the chosen week. Select Chris's work. At $40/hr it should review as $100 gross. If testing in another week, enter an Owner reason.
5. Expand Advances & Repayments; add a $50 TEST advance. Enter a $20 repayment, choose Zelle and review. Verify $100 gross / $20 repayment / $80 net.
6. Reports must show one $80 payment, $100 gross and $20 repayment. Payroll must show $30 outstanding and no payable Chris portion for that work. Repeat verification attempts must not create another payment.
7. Force-stop the app and reopen; then reboot Note 9 and reopen. Check the same payment, balance and paid/frozen task remain.
8. Finish Kam with 1.00 hour. Job becomes Complete; Kam's $35 is independently payable. Add a recheck labor line and assign Chris; the old Chris record must stay paid and frozen.
9. Choose Weekly Base TEST. Add eligible completed work, then enter base and hourly adjustment/reason separately. The same weekly base cannot be paid twice for the same Monday.

Do not uninstall/clear TEST app storage during persistence tests; that intentionally deletes its isolated database. Report failures with a screenshot and the action used.
