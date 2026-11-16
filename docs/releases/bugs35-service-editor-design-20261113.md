# Service Task editor — approved November 13 layout

Continues signed b4648 (`e606d4669ada240f29b066f781aafce730e00680`) on the existing release branch.

The Edit Service Task screen retained the old stacked controls. This change applies the Owner's approved editor reference: white surface, pale green job/vehicle header, readable section headings, paired mechanic/hours, paired formatted work dates, paired priority/status, green primary action and outlined Cancel. Narrow screens and large text stack pairs with spacing; the form scrolls while actions stay above the keyboard and Android navigation. Existing job headers open Job Details without saving or changing the task's job.

Paid labor shows a locked treatment and explanation. Existing field locks, task IDs, save validation, duplicate-save guard, historical reconciliation, invoice labor protections, and all local repositories remain unchanged. This presentation change does not migrate data, change payments, adjust payroll, or redesign other screens.

Verification includes rendered paid/unpaid editor fixtures, date editing with paid identity/hours preserved, job navigation independent of Save, single save during a pending operation, 150% text with keyboard, existing task scheduling and offline preservation, the Job Date/Title regressions, and Chris's 12h/$480 payroll case. Release upgrade verification starts from the signed b4648 APK and retains the permanent certificate and app data. Final CI results and artifact identity are recorded in the delivery report.
