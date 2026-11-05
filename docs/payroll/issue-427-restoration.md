# Tasks and Payroll restoration

The signed b2567 source is `267798b77403d147b4223927e863414931b616e4`.
The last recovered Tasks TEST source is `d92595b26dab21d19927cf9fac56305ab878b48c`.
PR #366 provides a status-policy checkpoint. Its code does not contain the later approved screens.
The recovered branch contains the amount selection, collapsed debt deduction, repayment validation, full-screen history, and flexible-pay refinements.
History sources include `00dd3bdf` for full-screen details, `b4617082` for links, and `ee6cbf4b` for the expansion hint.
Tasks Workspace sources include `8635bdf6` for Service and General Tasks, `1ea516fe` for the responsive filters, and `1bb039aa` for separate status pills.
Flexible payroll sources include `41644787` for the weekly settlement and `fa676b78` for net disbursement accounting.

| Surface | Approved source or contract | b2567 | Restoration status |
| --- | --- | --- | --- |
| Employee Details | Employee profile header and Details action, #427 | Edit form shows blank sensitive fields in Force Offline | Known roster name and position visible. Unavailable private details are explicitly labeled. Recovered profile header and Details action now open from the owner roster. |
| Employee Tasks | Original employee profile, #345 | Mechanic labor screen and invoice action | Recovered Service Tasks and General Tasks controls use employee-scoped records. General tasks persist locally. |
| Global and Job Tasks | Original Tasks workspace, #305 and #345 | Manual invoice action | Job menu opens Tasks and reads invoice labor using its actual invoice IDs. Recovered global Service and General Tasks workspace opens from Home, with job groups and task filters. Saved invoice labor derives stable tasks; edits and conversions update sources. Rechecks use separate identities and preserve original paid credits. Owner sync queues changed assignment snapshots with durable per-credit revisions; stale delivery cannot revert descriptions. |
| Weekly Labor Review | Original weekly review, #89, #335, #342 | Basic completed-work checklist | Recovered weekly review, carry-forward selection, fixed footer, and payment confirmation are bound to real completed credits. Mechanic estimated hours and actual completion are independent of billed hours. Selected partial minutes append immutable coverage, preserving the unpaid remainder. Cumulative integer rounding prevents fractional-cent overpayment across installments. |
| Payroll and Advances | Original employee profile, #341, #343, #399 | Basic totals and verified payment | Recovered summary cards, period filters, optional payment deductions, and standalone repayment form. Recovered opening-balance control and flexible weekly preview with locally saved defaults. Fixed and flexible weekly settlement uses selected outstanding credits, with base-inclusive or supplemental labor, adjustments, and debt repayment. Paid base is protected against repeat payment for the same employee/week. The restored all-employee Payroll overview uses actual work and settlement records. |
| Reports and week details | History panel and #371 | Flat payment history | Recovered period filters, weekly cards, full-screen details, frozen paid work and separate scoped Job and Invoice links. |
| Taxes & 1099 | Original employee profile | Employee details form | Recovered Taxes tab and Taxes & 1099 card. The original test kept tax calculations and filing disabled. |
| Owner payment authorization | #427 | One pinned payment phone | Unfinished release gate: the existing enrollment and repository still enforce the b2567 writer device. This must be replaced by safe transferable or coordinated Owner payment authority before this can be called the requested release. Removing the check alone would permit conflicting disconnected payments. |

## Reconciliation

Issue #372 reports different scopes in Tasks TEST. The restored history groups by the recorded payroll week and uses the verified settlement for gross, debt repaid, and transferred amounts. Frozen task allocations remain visible as work detail and are excluded from the settlement total calculation. The original TEST device ledger was not available to establish what created its historical $105 figure.

## Delivery gates

The current changes are a draft on the b2567 baseline. Remaining gates include complete UI parity/interaction evidence, coordinated any-Owner payment authority, final combined Android and iOS verification, physical shop Wi-Fi tests, and signed install-over verification. No production writes or migrations are part of this draft.

## Automated evidence and limitations

- `2396f093e5a53cedec4e4ab6d3b2ed89f0c36d9d`: diagnostics succeeded with 1,402 tests passed and one skipped (run 41972639430). This is evidence for the task/partial-payment/weekly-settlement milestone, not acceptance of later commits.
- `test/invoice_tasks_partial_payroll_test.dart`: uses regular application SQLite tables, saved invoices and assignments; edits/conversion, independent rechecks, three partial payments with restart, weekly supplemental and base-inclusive credit coverage, repayment and frozen history.
- `test/payroll_lan_workflow_test.dart`: three separate databases and signed loopback delivery; independent completion, partial pay to only one mechanic, lost acknowledgment/restart/retry, private mechanic scope, and stale assignment revision rejection.
- `test/payroll_period_totals_test.dart`: partial-paid minutes and settlement amounts reconcile without counting original hours twice.
- `test/payroll_overview_restoration_test.dart`: restored employee card routes the actual employee and selected week to review; checks the original carried-balance row and fixed footer.

Synthetic records only. No production financial records, phone storage or general synchronization were changed. Android compile is not install-over testing. Local/loopback tests do not establish physical Android/iOS or shop Wi-Fi acceptance. No consolidated release APK is certified by these intermediate checks.

### Identity reconciliation still to verify

Local estimate conversion is exercised through `OfflineDocumentDraftService` in `test/offline_estimate_to_invoice_create_test.dart`, including subsequent labor additions/edits. Syncing a provisional invoice later replaces document and line identities. The new task store does not yet carry proven source aliases through that remapping. That path must be finished before enabling payments on provisional invoice work; otherwise the permanent invoice could derive a second task for already credited labor. Existing frozen paid records must remain unchanged. This is unfinished application code, not a hosting or Owner credential dependency.
