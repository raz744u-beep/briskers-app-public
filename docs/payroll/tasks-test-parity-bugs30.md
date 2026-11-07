# Original Tasks TEST parity — Bugs 30

Reference: PR #258, exact commit `d92595b26dab21d19927cf9fac56305ab878b48c`.
Phone references: Owner files 31430.jpg (TEST Home), 31432.jpg (Payroll roster),
31434.jpg (Employee Tasks), versus regular-app failures 31424/31426/31428.jpg.
Base: integrated receipt source `8c7aea5fccefeaa76c1fb03b75f8502ac9708f57`,
which contains PR #430 `bc79769905ffd6ef6b82fa580d573715d0704397`.

**Status terminology:** restored in source is not phone acceptance. Automated
results and signed retention evidence must refer to the final exact commit.
No TEST fixture, TEST employee mapping, TEST payment or TEST database is imported.
Roster totals ignore employees with no records in the selected week, rather than
blanking other employees’ known totals. An explicit labor override now stays
manual when the same inherited mechanic is chosen; an Owner-confirmed missing
hourly rate applies only to unstarted, unearned, uncovered work. Paid rates and
historical snapshots remain unchanged.

| Original screen/workflow | Regular-app implementation and restoration | Evidence / remaining acceptance |
| --- | --- | --- |
| Home: separate Tasks, Payroll, Employees | Home has separate Owner entries; Reports retains its reports route. Payroll opens the weekly employee roster, never the single-employee reports dropdown. | Enabled normal-navigation test; Samsung appearance pending. |
| Main Payroll roster/week | `PayrollOverview` retains compact nickname cards, previous/next/calendar navigation, Hours/Gross/Paid/Balance, prior unpaid balances, Review Weekly Labor, fixed total footer. Card and labor action open the selected employee/week in Tasks. | Payroll overview and period-totals tests; enabled roster-to-payment navigation; phone pending. |
| Employee header/Details | Nickname-first header, legal name retained separately, original Details action, secure Owner-scoped private cache, roster first paint, auth cancellation/retry and expiry. | Profile lifecycle/Details security suites; physical OS challenge and private shop records remain phone-only acceptance. |
| Exactly Tasks / Payroll / Reports / Taxes | Four evenly spaced, kept-alive tabs; static Taxes info accessible independently of private ledger loading. | Profile lifecycle and normal navigation tests. |
| Tasks: Service / General | Original toggle and separate job-linked/general records, Service New Task and employee-first preselection, current work start/complete and estimates, no customer billing side effect. | Invoice assignment, general-task and production-screen suites. |
| Weekly labor selection | Original week arrows/calendar, unpaid and paid-history states, Select/Clear All, partial remaining hours, collapsed details, fixed Tasks selected/Selected this week/Available hours footer, Cancel/Verify Payment. | Original weekly UI retained; actual/credited hours and partial coverage tested against the real local ledger. |
| Payment verification/receipt | Method/date, calculated labor, explicit gross adjustment/reason, optional debt deduction, receipt and refresh. Real fenced authorization replaces TEST simulated posting. | Owner workflow, partial payment, roaming/delegation and LAN lost-response/retry tests. Never marks uncertain payment Paid. |
| Payroll tab/flexible weekly | Existing hourly/fixed/flexible weekly periods, weekly base, supplements/adjustments, opening balances, advances, standalone repayments and debt reconciliation retained. | Weekly/period and Owner screen tests, existing history retained. |
| Reports / full Payroll History | Original period filters, weekly cards, Load More/full screen, paid detail and Job/Invoice links use immutable recorded references. Gross/debt/transferred reconciliation remains ledger-based. | History restoration and accounting suites. Old unexplained TEST history is not reconstructed or imported. |
| Taxes | Original informational placeholder retained. | Intentional future: tax calculation/filing, not a missing implementation to fabricate. |
| Service Task filters/grouping | Active excludes completed canonical tasks; All includes completed work. Job cards sort on real local Job creation/date fallback, deterministic ID ties; tasks use invoice dates and saved source-line order. Number spelling never implies recency. | Bugs 30 ordering widget/pure tests; real phone source coverage pending. |
| Invoice labor recovery | Both cache reads and background recovery compare every known labor source; partially indexed invoices no longer skipped. Canonical task/line IDs reused; removed/void sources stay inactive; credits/payments/outbox never rewritten. Counts expose checked invoices, recovered labor and unavailable local details. | Partial-index/repeat/paid-credit/outbox/removed-line/void regression. Missing local snapshot remains unknown; no cloud fetch or invented labor. |
| Nicknames throughout | ID-scoped existing aliases decorate roster, filters, cards, Main Mechanic, split picker, weekly review and report selectors. Duplicate aliases include legal-name/ID disambiguation. Legal payroll names and historical paid snapshots unchanged. | Store and production navigation tests; editing real aliases offline requires phone acceptance. |
| Invoice/Job access and completed work | PR #430 Main Mechanic, split allocations, visible Tasks access and task-derived Work Completed retained with original history notes. | Existing regular invoice navigation, assignment, completed-history and recheck suites. |
| Receipt AI / original photos | #433 code from reviewed integrated #434/#432 source retained: independent HTTPS receipt gateway, secure Owner credential enrollment and explicit consent; read-only SAF folder reconnect/cached-photo fallback. | Receipt error/response, independent transport, photo scope/permission tests. Real credential, scan/save/reopen and Android folder-grant acceptance remain physical phone checks. |
| Numbering/totals | Approved #426 released-number suggestions, manual edits and original right-aligned financial summary retained. | Existing numbering and geometry regressions. |

## Safe adaptations from the TEST implementation

TEST-only simulated payments, separate `com.briskers.tasks_lab` entry point,
fixtures, hard-coded Job J-24 links and direct TEST payment-table writes are
excluded. Real app screens keep the approved UI but use shop-scoped canonical
invoice tasks, work credits and fenced Owner settlement. Unfinished TEST work
was allowed simulated pay; regular settlement requires confirmed earned work,
while a Job can remain open and another mechanic's labor remains unpaid.
Legacy draft-reading scaffolding in the reference has no current save path and
is not treated as a working accounting feature. Paid work is immutable; rechecks
receive separate identities. Full SSNs are never added to ordinary offline data.

## Release gate

Analyzer/full suite, enabled normal navigation, Bugs 26, Gloria, Android/iOS
compilation, signature/package/build inspection and signed b2568 install-over
with representative SQLite records and preferences, an intermediate update to
the checksum-pinned receipt build b2571, then candidate launch/restart retention.
One regular-app APK only. No live shop financial change, Supabase migration,
outbox replay, Force Offline change, uninstall or app-storage clearing.
Physical Owner phone acceptance is reported separately, never inferred from CI.
