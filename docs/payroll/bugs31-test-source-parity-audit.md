# Bugs 31 — Original Briskers Tasks TEST to regular-app parity audit

Reference commit: `d92595b26dab21d19927cf9fac56305ab878b48c` (PR #258).
Regular source branch: `fix/bugs31-payroll-navigation-noop-auth-20261106`.
Owner visual references: ten photos of original installed offline Tasks TEST shared Nov 6, 2026. Photos are conversation uploads, not checked into this repository.

This is an implementation/source checklist, **not** physical-phone acceptance.

| Original TEST screen / behavior | Exact TEST source | Regular Briskers source | Current status and safe next step |
| --- | --- | --- | --- |
| Weekly all-employee Payroll roster, nickname cards, totals, outstanding and Review Weekly Labor | `lib/tasks_lab/payroll_overview_screen.dart` | `lib/screens/payroll/payroll_overview.dart` | Corresponding controls/labels in source; verify geometry, calculations and route on Samsung |
| Employee Profile header, Details, four tabs | `lib/tasks_lab/employee_payroll_profile.dart` | `lib/screens/payroll/owner_payroll_screen.dart` | Tab labels in source; regular tab spacing adapted to even widths. Verify visible local data without repeated prompts |
| Tasks: Service/General toggle and week work selection | `lib/tasks_lab/employee_payroll_profile.dart` | `lib/screens/payroll/owner_payroll_screen.dart` | Code present; confirm week arrows, paid history, zero/partial hours and disabled Verify Payment states |
| Global Service Task grouping, filtering, create task and job drilldown | `lib/tasks_lab/tasks_workspace.dart` | `lib/screens/payroll/tasks_workspace.dart` | Filtering/grouping and Service New Task present. Exact TEST per-job Add Recheck action was missing and is restored in PR #444; phone acceptance pending |
| General Tasks statuses and creation | `lib/tasks_lab/tasks_workspace.dart` | `lib/screens/payroll/tasks_workspace.dart` | Controls present; PR #444 removes irrelevant OS payroll-payment unlock for task status edits. Verify normal role and local persistence |
| Individual invoice labor allocation and credited mechanic hours | TEST integration into job document, source/fixtures in PR #258 | `lib/screens/jobs/job_document_screen.dart`, `lib/screens/payroll/owner_payroll_screen.dart` | Distinct invoice quantity vs mechanic hours preserved by current source design; verify owner screenshot per labor row, split allocations, paid locks |
| Weekly Labor Review, fixed footer, partial payment and verification | `lib/tasks_lab/weekly_labor_review_screen.dart` | `lib/screens/payroll/weekly_labor_review_screen.dart` | Structural source counterparts exist. Real ledger authorization differs intentionally from TEST simulated payments; paid-credit idempotency required |
| Payroll tab period summaries, prior balances, advances/repayments | `lib/tasks_lab/employee_payroll_profile.dart` | `lib/screens/payroll/owner_payroll_screen.dart` | Corresponding source controls present; test actual ledger values, adjustment/repayment and read-only access without OS prompt |
| Payroll History in Reports | `lib/tasks_lab/payroll_history_panel.dart` | `lib/screens/payroll/payroll_history_panel.dart` | **Visual/semantic variance found:** original cards use Paid/Partial/Unverified, show Hours/Gross/Paid/Balance. Regular shows Recorded with Hours/Gross/Debt repaid/Transferred. Keep actual settlement/debt values accurate; restore visual equivalence only with real underlying balance and paid-status evidence, never invent it |
| Taxes placeholder | `lib/tasks_lab/employee_payroll_profile.dart` | `lib/screens/payroll/owner_payroll_screen.dart` | Informational placeholder by design; real tax/1099 calculations not implemented in TEST |
| Single signed-in Owner view; OS prompt only on payroll payment | Original TEST had isolated simulated auth/payment | `lib/services/device_owner_authorization.dart`, `lib/screens/payroll/owner_payroll_screen.dart` | Intentional secure production adaptation. PR #444 fixes navigation, status, hour, assignment picker prompts. Remaining assignment, recheck, LAN and payment calls require action-by-action audit |
| Original TEST job recheck remains separate from paid work | `lib/tasks_lab/tasks_workspace.dart` | `lib/screens/payroll/tasks_workspace.dart`, `owner_payroll_screen.dart` | Per-job Add Recheck restored by PR #444, but must verify real job ID and immutable paid task history after save/restart |

## Must not copy from TEST

The separate TEST package, seeded employees/customers/jobs, direct simulated payment recording, hard-coded J-24 buttons and any TEST-only expense/sync data cannot be merged into production. Preserve canonical job/invoice IDs, shop business scope, local SQLite/outbox and immutable paid allocations. Valid Briskers Owner session grants screen viewing; actual payroll payment still requires focused authorization.

## Release / proof gate

1. Run original TEST visual baseline tests against TEST, and corresponding production navigation/payroll/invoice regression checks against *final integrated source*.
2. For the identified Reports variance, distinguish paid gross, net transferred, repayments, outstanding and unknown states using actual ledger data; never relabel a partial settlement as fully paid or treat transferred net as gross.
3. Verify each original screenshot's screen/state on Owner Samsung with Force Offline ON, including repeated tab navigation without unlock prompts.
4. Verify actual paid work, rechecks and role changes with controlled test records. No actual shop payroll payment required for QA.
5. Pass complete CI and signed install-over/backout checks; separately verify the private internet receipt gateway on the device; do not ship this draft patch alone.
