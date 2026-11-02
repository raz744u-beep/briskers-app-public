# Briskers Tasks/Payroll — integrated offline implementation gate

Baseline: Note 9 synthetic smoke APK, commit c3aa7077be567d29f8752fa03ef5179ed5a1d846, user-confirmed November 2, 2026. This branch is separate from production and keeps the smoke build intact.

## First implementation slice — genuine payroll credits

Use business-scoped local Job, labor-line, task, mechanic-assignment, and employee IDs. An earned payroll credit is one immutable mechanic/task portion, with its own actual hours and rate snapshot. Never infer pay from an invoice total alone. On multi-mechanic work, completing one portion may make that portion payable while the shared task remains in progress.

## Payment rules

Owner selects finished and unpaid credits for a chosen week, with an optional Owner override and audit. At Verify Payment, require amount, method, verification date and any chosen repayment. Gross earnings are preserved; repayment reduces net and the outstanding advance only by the explicitly entered amount. Fixed weekly base and hourly components must remain independently adjustable for eligible employees.

A single **local database transaction** must re-read the selected credit versions, reject paid/reserved/changed credits, insert immutable payment and credit allocation records, update advance balance, write audit/history, and enqueue an idempotent sync operation. A retry with the same operation ID and payload returns the existing transaction; a conflicting replay must fail. Database failure rolls everything back. Paid allocations remain frozen even after task reopening/recheck.

## User interface

Employee profile uses Details, Tasks, Payroll, Reports, Taxes & 1099. Payroll tab: current-week selection, unpaid balance, collapsed Advances & Repayments. Reports tab: historical payments and filters. Verify Payment confirms method, amount, repayment, and selected credits; after local transaction commits, update visible lists instantly without server round trips. Keep staging vs paid distinct.

## Acceptance before integrated APK

- Two mechanics on one task; one finished and payable without the other
- One-to-many labor lines and time edits; hours credited only on completion
- Partial jobs payable without closing Job or Invoice
- Full payment + job completion prompts leave final closure authoritative
- Reopen/recheck preserves previously paid hours
- Duplicate Verify and concurrent attempts do not double pay
- Repayment decreases advance exactly once; gross stays constant
- Force Offline: payment/paid history persists after process restart and device reboot
- Interrupted local transaction leaves no partial records
- Different businesses and non-Owners cannot access or finalize other payroll
- No changes to real payments, schema deployment, production app, or main until independent acceptance

## Scope guard

Do not treat synthetic in-memory staging as durable payroll. Supabase is background synchronization only, never required for local UI or local Owner actions. Keep tests and integration on this branch; create separate signed APK with appropriate package identity for user acceptance.
