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
| Owner payment authorization | #427 | One pinned payment phone | Permanent writer restriction removed. Existing Owner unlock authorizes payments on Android or iPhone. An encrypted LAN handoff transfers the reconciled ledger and exclusive payment capability; the sender is fenced before the receiver can pay. A disconnected non-holder retains a durable pending request. No special Owner codes or replacement signing identities. The original installation identity is a migration trust origin only, not a permanent payment device. |

## Reconciliation

Issue #372 reports different scopes in Tasks TEST. The restored history groups by the recorded payroll week and uses the verified settlement for gross, debt repaid, and transferred amounts. Frozen task allocations remain visible as work detail and are excluded from the settlement total calculation. The original TEST device ledger was not available to establish what created its historical $105 figure.

## Delivery gates

The changes preserve the b2567 baseline and the recovered screens. Release requires the exact combined source to pass diagnostics/full regressions, Android compilation, iOS compilation and Gloria regression, followed by permanently signed Android packaging and an emulator install-over test from b2567. Physical shop Wi-Fi and platform biometric acceptance remain separate. No production writes or backend migrations are part of this release.

## Automated evidence and limitations

- `2396f093e5a53cedec4e4ab6d3b2ed89f0c36d9d`: diagnostics succeeded with 1,402 tests passed and one skipped (run 41972639430). This is evidence for the task/partial-payment/weekly-settlement milestone, not acceptance of later commits.
- `test/invoice_tasks_partial_payroll_test.dart`: uses regular application SQLite tables, saved invoices and assignments; edits/conversion, independent rechecks, three partial payments with restart, weekly supplemental and base-inclusive credit coverage, repayment and frozen history.
- `test/payroll_lan_workflow_test.dart`: three separate databases and signed loopback delivery; independent completion, partial pay to only one mechanic, lost acknowledgment/restart/retry, private mechanic scope, and stale assignment revision rejection.
- `test/payroll_period_totals_test.dart`: partial-paid minutes and settlement amounts reconcile without counting original hours twice.
- `test/payroll_overview_restoration_test.dart`: restored employee card routes the actual employee and selected week to review; checks the original carried-balance row and fixed footer.

Synthetic records only. No production financial records, phone storage or general synchronization were changed. Android compile is not install-over testing. Local/loopback tests do not establish physical Android/iOS or shop Wi-Fi acceptance. No consolidated release APK is certified by these intermediate checks.

### Document identity reconciliation

Local estimate conversion is exercised through `OfflineDocumentDraftService` in `test/offline_estimate_to_invoice_create_test.dart`, including subsequent labor additions/edits. Syncing a provisional invoice later replaces document and line identities. The draft replay transaction now retains task identities when every ordered source line agrees exactly with the successful replay response. Current invoice/line and Job references change only on the derived source records; earned credit IDs and frozen payment snapshots remain unchanged. Missing or conflicting provenance fails reconciliation instead of guessing from amounts. A regular conversion regression now pays a real local work credit before replay, then checks one paid credit and current Job/Invoice links after replay. Final combined tests and multi-device replay verification remain required.

## Portable Owner payment coordination

The existing local Owner authentication remains unchanged. Settings → Employees → Wi-Fi connects approved Owner devices on the same private network; approval uses the existing Owner unlock. Device keys and per-employee pairing secrets stay in secure storage. An Owner certificate authorizes the new Owner route for existing mechanic links, without requesting mechanic re-enrollment. No account, Supabase or internet connection is needed for payroll.

The currently reconciled ledger capability can move between Owner devices. Transfer fences the sender before exporting a recipient-bound signed lease. A device may finalize offline only while holding that capability. Losing the transfer response, delivery acknowledgment or application process cannot create another active payer: durable offers, acquisition IDs, protected epoch counters and immutable payment coverage recover the same operation. There is no timed election while disconnected. A non-current Owner can start a payment; it stays explicitly pending until current state is available. Reports preserve verified receipts separately from pending requests.

| Automated acceptance | Production path exercised | Evidence boundary |
| --- | --- | --- |
| `payroll_owner_roaming_test.dart` | Two independent Owner SQLite databases and secure stores; real signed/encrypted loopback, concurrent payment acquisition, lost transfer response, interrupted secure activation, restart and duplicate attempts | Native test processes and loopback, not physical phones |
| `payroll_owner_mechanic_delegation_test.dart` | Two Owners plus two mechanic databases; approved Owner route transfer, original Owner offline, independent completion, pay only one, lost receipt response, restart and exactly-once delivery | Authenticated local grant and pairing classes; synthetic financial records |
| `payroll_owner_screen_workflow_test.dart` | Regular restored employee Tasks → Verify Payment → Reports, actual SQLite persistence; current-holder payment and disconnected pending request after reopening | Flutter widget automation, not physical biometric/Wi-Fi acceptance |
| Existing invoice/weekly/LAN suites | Real saved labor, edits and conversions, rechecks, partial installments, flexible base/supplements, repayment, frozen history, private mechanic scope | Synthetic records only |

Final exact-commit CI and signed APK evidence must be recorded in the delivery manifest after those jobs finish; test names alone are not a passing result.

## Included / Not included / Needs phone testing

- Included in source: recovered profile, Tasks, Payroll, Reports, full-screen history, Advances/Repayments and original Taxes placeholder; invoice-derived work, independent mechanic credits, rechecks, partial payments, weekly settlement, portable Owner payment coordination and LAN receipt delivery. Existing daily-use fixes remain in history.
- Not included: live tax filing/calculation (never part of recovered TEST), production historical record corrections, general synchronization enablement or new backend deployment. Receipt gateway deployment, offline recurrence editing/generation and J-18/Worldpac provenance remain outside this payroll change and are not newly claimed complete.
- Needs phone testing after automated gates: install the signed update without uninstalling, retain Force Offline and verify familiar data; same-Wi-Fi Owner approval and Android/iPhone unlock; two mechanics complete a shared open Job, pay only one, interrupt/retry and restart, verify one receipt in Reports and the second mechanic unpaid. A pending request must not be treated as a paid receipt. Never use a second real payment to test retry behavior.
