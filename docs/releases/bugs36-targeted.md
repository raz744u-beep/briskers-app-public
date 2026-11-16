# Bugs 36 — targeted Owner release

Continues verified b4649 (`ea18b198692cd60742afb4c697d368e0b0d0d5cf`) on the existing Bugs 35 branch. Tracking: #455; previous requirements and Owner evidence: #454.

## Included

- Owner can replace or split an unpaid mechanic allocation after Done, including on Paid/Closed customer invoices. Replacement retains the task, original state and completion date; the old allocation identity remains as an audited, inactive zero-credit record. The new mechanic uses the saved compensation rate. Same-mechanic hour corrections retain the allocation ID. Save-operation replay does not create another task or wage credit.
- Paid, partially covered, and Owner-reconciled wages remain protected. These changes do not implement a new paid-wage adjustment workflow. Historical recordkeeping remains separate from earned/payable labor.
- Invoice-derived task text is editable without changing invoice lines. A local override survives invoice-source refresh. No migration changes the J-56 typo or any actual customer record.
- Compact Service/General Tasks header, search with adjacent filter, task count and New Task row; one-line collapsed descriptions; full text on tap; separate long-press Edit Task/Edit Assignment/Mark Done actions. Employee Work Review remains read-only with one-line descriptions and full read-only details on tap.
- Compact scrolling filter sheet with a pinned teal Apply button above system navigation and keyboard. Active default remains explicit; Show all task statuses preserves access to completed/history rows.
- New labor dates explicitly inherit Job Date. Job Date edits move only explicitly inherited dates. Choosing task dates—even the same calendar dates—marks a manual override. Legacy dates of uncertain origin stay unchanged. Description/assignment/hour edits do not break inheritance. Completion timestamps and financial/payroll payment records are independent.
- Task text/date provenance is persisted locally and included in Owner-ledger transfer; paired mechanic assignment snapshots include date metadata. General reminder dates are independent.

## Verification

Focused SQLite tests cover the Chris 5h/$200 to Kam 5h/$175 transfer, separate 18h Not Started task, retries, restart, round-trip reassignment, split assignments, paid/partial-paid protection, text-only edits, invoice-source replay, conservative/manual date inheritance, Owner-ledger sync and paired-mechanic sync. Existing Chris 12h/$480, historical cutoff, invoice closure/payment, receipts and recurring-expense regressions are retained.

Widget touch tests exercise separate tap/long-press actions, completed invoice task editing, compact cards and safe Apply/Save controls at 412×915 with a 32px navigation inset and 300px keyboard. Screenshots are captured from the actual Flutter widgets, not generated mockups. Physical S26 Ultra interaction remains Owner acceptance testing.

The permanent-signing workflow gates APK publication on Diagnostics/iOS compatibility and Android build tests. Install-over retention uses the original package/certificate and b4649 as the immediate baseline, with a synthetic local database, saved preferences and receipt photo. No production phone is uninstalled, reset or modified by this verification. Release evidence is delivered with the final APK.

## Reminder functionality deferred

Existing General Tasks retain local date/time, assignee, optional job, reminder lead time and device-local Android/iOS scheduling without a Start requirement; completion does not create labor payroll. Local notification permission is required and Android uses inexact scheduling. Automatic delivery/scheduling on assigned employees' other phones and end-to-end iPhone notification delivery are not established by this release and remain future work. No additional reminder transport was introduced.
