# b2568 Tasks and Payroll correction — Issue 429

Baseline: signed b2568, commit 51d214a1593c7a73c9091cf930fa920a928b7c69.
This is a correction of the restored regular application, not a new payroll UI.
PR 430 retains that baseline and the original combined source in ancestry.

## Screen comparison

“Corrected in source” is not a claim of phone acceptance. Final exact-commit CI,
signed packaging and installation evidence belong in the delivery manifest.

| Approved screen or control | b2568 problem | Correction and evidence |
| --- | --- | --- |
| Employee profile header and Details | Known employee present but private tabs stalled behind unlock/loading | Known header remains immediately visible. Authorization, database reads and optional LAN refresh have independent bounded lifecycles. Cancellation, timeout, retry and grant-expiry widget tests use the production screen. |
| Four Tasks / Payroll / Reports / Taxes tabs | Left-aligned scrollable tabs, content unavailable during loading | Four equal-width tabs remain navigable. Kept-alive tab content and PageStorage retain selection and scrolling across refresh. Static Taxes information does not need payroll unlock. |
| Employee Details | Optional nickname and remote details delayed the whole form | Known legal name/position paint first; nickname has independent timeout/retry. Existing Owner online editing remains. Previously verified private information has an explicitly authorized encrypted, shop/Owner/employee-scoped offline cache. No full SSN is cached. Missing offline information is labeled unavailable. |
| Invoice and Job Main Mechanic | Missing from visible content | Visible optional selector defaults to Unassigned, uses actual employee IDs and local nicknames. Changes affect only inherited/unstarted allocations; explicit, earned and paid work remains intact. Later invoice labor inherits the saved main mechanic. |
| Per-labor mechanic action | Hidden behind invoice action sheet | Each invoice labor row shows saved assignment state and opens the same linked task for override/split and independent estimated, actual and credited hours. No changes to customer quantities, prices or totals. |
| Job tasks access | Popup-menu-only entry | Visible Tasks action in Job content and invoice content, plus existing navigation. Both use the canonical task IDs. |
| Global Tasks workspace | Service Tasks creation absent | Original Service/General organization, filters and cards retained. Service New Task selects an employee, existing open Job or explicitly creates a customer/vehicle-associated Job. It creates no invoice charge. General Tasks require no Job/customer. |
| Employee Tasks | No employee-first service creation/current-work access | Service New Task preselects the employee. Current assigned work exposes Start/Complete and estimates; original embedded weekly labor review remains. Separate rechecks retain original paid work identities. |
| Weekly labor review | Previously restored controls needed integrated verification | Original task selection, carry-forward, partial hours and fixed footer retained. Short/error-constrained viewports scroll rather than overflow. Real credit balances feed hourly/fixed/flexible weekly settlement, base, supplements and adjustments. |
| Payroll / Advances & Repayments | Preserve approved full functionality | Original period cards, opening balances, advances, optional debt deduction, standalone repayments and verified settlement stay connected to the same ledger. Covered work and weekly base cannot be offered twice. |
| Reports and full-screen payroll history | Preserve approved layout and references | Original weekly cards, filters, Load More, full-screen paid work, Gross / Debt Repaid / Transferred and Job/Invoice links retained. History totals use recorded settlements, not a second sum of task snapshots (#372). Original TEST device records underlying the historical discrepancy are unavailable; no historical repair is claimed. |
| Taxes & 1099 | Placeholder appeared blank while authorization stalled | Original informational placeholder remains accessible. Tax calculation and filing are intentionally not implemented. |
| Completed work / Service History | Separate manual Work Performed entry and billed-labor summary could imply completion | Read-only Work Completed derives confirmed task descriptions, mechanic nicknames and actual hours for the correct Job/customer. Manual historical work notes and visit relationships remain in place as Work Notes. Billed labor is explicitly a billing reference, not evidence of completion. Local history search includes completed tasks and existing notes. |
| Invoice/Estimate financial summary | Amount column changed from approved Expanded to Flexible | Exact approved PR 426 financial-summary blob restored. Plain and colored rows have the same horizontal amount edge. No calculations or stored values changed. |
| Released invoice/Job number pool | PR 426 additions absent from signed b2568 | Approved number-pool selectors and protected local reuse allocation restored with their SQLite regression tests. Existing manual Job-number edits remain. |
| Invoice pinned tab strip | Enabled regular-navigation test found mismatched sliver geometry | Tab strip now paints its declared height; same labels and design. |
| Offline linked Expenses tab | Offstage future could fail before the tab subscribed | Expense loading begins when the real tab mounts; unavailable cached data appears as the existing explicit error state rather than an unhandled startup exception. |

## Data and payment integrity

- Additive metadata stores assignment provenance, actual work time and versioned
  Job leads alongside the existing task, work-credit and payment ledger.
- Main-mechanic changes never delete credit, payment, document or pending-operation
  identities. Retired inherited work delivered after a disconnected completion
  is retained for explicit Owner review and is not automatically payable.
- Signed Owner work snapshots carry actual and credited time separately.
  Mechanic receipts reconcile that work state before validating paid coverage.
  Older versions cannot overwrite newer progress; covered work stays immutable.
- Existing Owner authentication and portable, fenced LAN payment coordination
  remain. No permanently designated payment phone or new Owner code is required.
  A device lacking verified current payment state keeps a durable Pending request.
- Cross-version Owner ledgers fail closed with an update message. Use the same
  candidate version on all participating test devices before Wi-Fi acceptance.
- No production migration, production financial edit, general sync, change to
  Force Offline, phone uninstall or storage clearing is included.

## Automated acceptance

| Test path | Production behavior exercised |
| --- | --- |
| b2568_regular_navigation_test.dart, payroll-enabled invocation | Real offline invoice screen, Main Mechanic, labor override and shared allocations, independent completion, actual/credited time, employee weekly review, payment and Reports. Real SQLite records, normal production widgets and application theme; no network. |
| b2568_assignment_integration_test.dart | Synthetic invoice 6363 / J-44-like turbo labor; inheritance, explicit override, two-mechanic split, invoice edits, separate hours, partial then full settlement, restart, paid protection and late disconnected assignment review. Never touches the real invoice. |
| b2568_profile_lifecycle_test.dart | Immediate evenly spaced tabs, slow SQLite, authentication cancellation/retry, timeout and expiry without navigation lock or duplicate reads. |
| b2568_employee_details_test.dart / b2568_details_security_test.dart | First-paint known roster data; optional nickname timeout; secure Owner/shop/employee scope, expiry/revocation and SSN whitelist. |
| b2568_financial_right_edge_test.dart / available_number_pool_test.dart | Approved amount-column geometry at several widths/scales; local released-number reuse and protections. |
| payroll_lan_workflow_test.dart | Three separate persisted databases and signed loopback: two independent completions, one employee paid, partial/full receipts, actual/credited differences, lost acknowledgment, restart/retry, one receipt, other employee unpaid and privacy restrictions. |
| Existing Owner roaming/delegation and screen workflow suites | Two Owners, two mechanics, fenced capability transfer, concurrent/lost-response/restart handling, disconnected Pending and Reports persistence. |
| Existing invoice/weekly/period/overview suites | Real invoice edits/conversion/replay, separate rechecks, partial coverage, flexible/base-inclusive/supplemental weekly pay, advances, repayments, history reconciliation and restored navigation. |

All records used in automation are synthetic. The enabled-navigation test is
run separately with BRISKERS_ENABLE_OWNER_PAYROLL=true; it is intentionally
skipped in the default feature-disabled regression invocation. Default skips
must be reported separately from passing tests.

## Included / Not included / Needs phone testing

- Included in this correction: the source corrections above and all preserved
  b2568 daily-use fixes. No unrelated experimental branch is merged wholesale.
- Not included: actual tax filing/calculation; repairs to production historical
  invoice references or missing source photos; a claim that the old TEST ledger's
  unexplained historical amount has been reconstructed; new receipt gateway
  deployment or new offline recurrence editing/generation.
- Needs phone testing: actual Owner biometric cancellation/retry and offline
  cold start; responsive appearance on the S26 and iPhone/iPad; approved employee
  details and history against the shop's existing records; physical shop Wi-Fi
  pairing, disconnect/reconnect and one-payment delivery across real devices.
  These are distinct from automated SQLite/loopback/widget/emulator checks.
- Signed APK delivery is gated on final diagnostics, complete regressions,
  Android compilation, iOS compilation, permanent certificate/package checks and
  b2568 install-over retention. The Owner's existing device is never modified
  by automated acceptance.
