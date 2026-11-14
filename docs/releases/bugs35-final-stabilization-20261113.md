# Bugs 35 — November 13 stabilization

Continues PR #447 / issue #454 from e52b9793a195b44de23eaf61748898cc9fe00b05 (signed b4645). The Owner's phone confirmations are the baseline: Gloria/Rick/Reginald closed, J-48/J-49 historical wages reconciled, Chris November 9–13 unpaid labor 12 hours / $480. No production customer payment, expense or payroll record is rewritten by this change.

## Included changes

- Owner labor editor: one scrollable form with job, description, mechanic shares, assigned hours, editable Start/End dates, priority, work status and payroll treatment. Historical and Done tasks remain date-editable, including zero-hour historical records. Paid allocations retain their hours, identities and status. Existing invoice-service assignment and explicit new-job creation remain available. New creation uses one operation identity and an atomic local transaction.
- Task schedule lives in separate SQLite metadata. Newly projected invoice labor gets creation-day defaults; replay keeps existing dates. Owner edits never rewrite payroll completion/payment dates or customer charges. Work Review filters by the edited work-date range. The previously identified J-40 Oil Separator allocation receives the Owner-specified November 9–10 dates, unless the Owner already edited them. J-48/J-49 actual dates are never guessed.
- High red / Normal green / Low light-gray trailing flags. Overdue remains separate from work status and is suppressed for Done work.
- General Task creation/editing uses a matching keyboard-safe form with assignee, optional job, due date/time and optional local device reminder. Stable notification identity replaces earlier schedules; Done, disabled and removed tasks cancel reminders. Android reminders use inexact idle scheduling and may be delayed by the OS; notification permission is requested only when the user enables a reminder. Cross-device reminder delivery is not introduced.
- Employee Tasks remains read-only. Payroll keeps the working eligibility, adjustments, advances, repayments and payment protections. Equal-height summary tiles, dark combined job/customer links with independent checkboxes, dark descriptions and bottom safe areas address the approved layout corrections.
- Jobs use stable descending creation order, with numeric job-number tie breaks. Normal Owner status choices are Open, In Progress, Completed and Closed; stored legacy status history is retained. Shared compact list cards now have the approved pale full-card status tint. Search hints use “Tap to open · Long press for options.”
- Larger scrollable delete/reconciliation confirmations keep action buttons visible and describe the actual affected records. Historical wage reconciliation creates no payment or expense.
- Existing Cintas offline editing/generation, local invoice finalization/closing, historical payments, receipt photos, Mark All Done and payroll protections remain in the consolidated source.

## Verification

Local verification includes persistent SQLite date edits on closed jobs, paid-marker/credit preservation, Owner-ledger transfer, weekly review filtering, the exact Chris $480 acceptance calculation, duplicate payment rejection, reminder replacement/cancellation and General Task persistence. Widget tests exercise the real editors, payroll selection/navigation, date controls and confirmation buttons at phone dimensions with keyboard/navigation insets. Existing Cintas, closure, payment, receipt and payroll regressions remain required.

Release gates require clean analysis, the full regression suite, enabled Tasks/Payroll navigation, Android and iOS compilation, recurrence/retry protections, permanent-certificate verification and a data-preserving Android install-over chain through b4645. Build number must exceed 4645. Final build/commit/artifact evidence is reported with the delivered APK, not inferred from this source document.

Physical-phone follow-up: the Owner must enter the actual J-48/J-49 work days. Screenshots and database regression fixtures are synthetic; they do not substitute for inspection of the Owner's private phone database. Recurring expense catch-up retains the existing app-open/resume behavior. Reminders on another employee device require that device's own saved task and notification permission.
