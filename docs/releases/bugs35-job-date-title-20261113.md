# Bugs 35 — targeted Job Date and Job Title release

Continues verified b4646 / 381be4b9 on the existing PR #447 branch. Scope is the two Owner corrections in issue #454 comment 6855128178.

- Create Job and Edit Job have Job Date, defaulting to the America/Chicago calendar date. The value is stored separately in local SQLite, inside the existing create/edit transaction. Original created_at and invoice/payment/payroll dates are untouched.
- Only newly generated invoice labor tasks inherit Job Date as Start and End dates. Existing tasks and Owner overrides remain unchanged when Job Date is edited or invoice details replay.
- A meaningful Job Title wins on compact Jobs cards. Blank and generic legacy Invoice titles use saved repair/labor text. Titles are optional in both forms. This is display resolution, not replacement of invoice labor descriptions. Search supports saved title, requested work and cached invoice line descriptions.
- No task-editor redesign, palette changes, payroll calculations, closure changes or recurring-expense changes are included.

Focused verification covers Chicago date boundaries/DST, last-week task-date inheritance, unchanged existing schedules and creation timestamps, persisted Job Date after SQLite reopen, unchanged financial rows, title save/reopen/fallback/search, actual Create/Edit form rendering and editing, existing creation-order tests, historical paid-task protections, and Chris's 12 hours / $480 case.

Release keeps the permanent package/signing identity, requires a version above 4646, and tests normal Android installation over signed b4646 with retained synthetic records/preferences/receipt image and app restart. Physical Owner-phone acceptance remains separate from emulator and widget evidence. Existing jobs receive no guessed historical Job Date; the default is shown until the Owner saves a date.
