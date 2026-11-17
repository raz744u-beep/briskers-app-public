# Bugs 36 — approved four Tasks screens

Continues verified b4655 (`98af6b0b4d5fc02d7bd2cde7b48833dc46337a00`) on PR #447, issue #455. Scope is the four Owner-supplied November 14 visual references, not other screens or business logic.

## Included

- Global Service/General Tasks: flat compact white cards, priority-colored edge, task icon, one-line title, job/customer and actual assignments/hours; separate priority dropdown and status badge. Teal tabs, search/filter row and count/New Task row.
- Job Tasks: branded job/customer header, vehicle strip, paired creation buttons, Mark All Done beside completion count/progress; compact status-colored edges/icons and separate priority/status badges. Tap opens Details; long press retains protected edit, assignment, completion and historical reconciliation actions.
- Dedicated Task Details: job/vehicle/status, invoice link, full task description, actual mechanics/hours/work dates/payroll classification, priority selector, Start/Finish/Mark as Done and Edit Task/View Job actions. Existing editor supports completed and historical work. Details reloads after changes and waits for pending local reads.
- Employee Tasks: branded identity and existing four tabs, read-only Work Review, Monday–Friday selector, currently assigned jobs, weekly status totals/completed-unpaid hours and task cards. Existing weekly filtering and paid classifications remain unchanged; Payroll, Reports and Taxes bodies are unchanged.

## Preservation

No payment, payroll calculation, invoice, expense, dashboard, receipt or recurring-transaction implementation changes. Task identity, assignments, completion and date inheritance continue through the existing protected repository operations. No example customer/task records are imported or rewritten.

Priority-only changes use the existing schedule revision when available. An additive local priority metadata table handles General Tasks and unscheduled legacy labor without inventing work dates, breaking inheritance, changing status, or modifying payroll. General/legacy priority metadata is local; cross-device delivery of that new metadata is not claimed. Scheduled labor priority uses the existing ledger synchronization path. Existing reminder dates remain independent.

## Pre-build rendered comparison

Five actual Flutter captures cover all four routes (both global tabs), plus filters with keyboard/navigation insets, using the production shared widgets/theme at 412×915. Reference gallery controls/black margins are excluded from app content.

The reference layout, separate status/priority, navigation and button grouping are restored. Remaining differences reported before building:

- Native Roboto/Material icon shapes and the repository's existing Briskers wordmark differ slightly from the illustrated artwork. Header wave, shadows and fills are Flutter-rendered, not pasted screenshots.
- Actual saved descriptions, hours, counts and stable newest-first ordering replace mock example values. Full details preserve the original task description rather than inventing a second description.
- Existing Active filtering continues to exclude Done tasks; Done work is available through All/Done/paid filters even though the reference shows a Done example under Active.
- Long descriptions and accessibility sizes wrap in Details; list descriptions remain one line. Start/Done controls are shown only when applicable and permitted, including paid/historical protection. The existing Overdue indicator remains independent of status.

The Owner's physical phone and production database are not accessed. Phone-sized widget captures and isolated Android upgrade tests are verification evidence, not physical S26 Ultra acceptance. Release remains for Owner visual approval.

## Verification plan

Focused coverage: all four routes, independent tap/long press/priority, completed-paid editing, local Details refresh after Done, weekly totals/filtering, safe-area filters, priority-only paid/unpaid preservation and restart/scheduled-labor ledger round trip. Full Flutter regressions, analyzer, enabled regular payroll navigation, signing/candidate gate tests, exact-source Android/iOS CI and b4655 install-over retention are required before delivery. Final results, commit/build, signature and artifact hashes are recorded in the delivered verification report.

Cross-device employee reminders and end-to-end iPhone notification delivery remain deferred; no new reminder infrastructure or unrelated features are added.
