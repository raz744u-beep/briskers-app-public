# November 14 Owner quick fixes

Continues verified b4656 (`d24de41377766692bf54a847f14dc72201223f00`) on the existing Bugs 36 / PR #447 branch. Scope comes from `Briskers_Quick_Fixes_Work_Handoff_2026-11-14(1).zip`, README_START_HERE.md.

## Included

- Compact unpaid payroll rows: one-line descriptions, separate checkbox, job link, right-aligned hours/amount, accurate Select All / Deselect All. Expansion shows full description, exact saved View Task and existing partial-pay hours editor. No calculation changes. Task Details loads all allocations of the task even when entered through one employee's payroll.
- Employee roster: nickname and legal name on line one; role and actual authorized pay information on line two. Existing IDs, permissions, role styling, navigation, actions and compensation lookup retained.
- Profile tabs: only the selected section is colored; others neutral. Shapes/order/content unchanged.
- Android reminders: explicitly retain dynamically referenced notification drawable through release resource shrinking and use the same icon in notification details. Both generated Android runners contain required notification permissions/receivers.
- General Task completion: notification failure can no longer suppress a successful local-save reload. A plain-language reminder warning replaces the raw platform exception. Finish updates the saved task; it does not delete it or create payroll. Active excludes Done by design. The existing empty-list Show all task statuses action also works for General Tasks.

## Asset-dependent item

**BLOCKED: logo v3 replacement.** No identifiable approved brighter-blue/subtle-grille/no-badge source artwork was available in the ZIP or the relevant asset search. No logo artwork, cropping, colors or lettering were changed. The mockup logo was not copied or recreated.

## Verification

- Flutter tests cover equal-height rows, checkbox/expansion/job/task independence, exact task IDs and all saved allocations, return scroll/selection, partial-pay draft values, tab colors, employee rows at 412 and 360 logical pixels, General Active/All/Done visibility, completion with injected Android icon failure and job-history retention.
- Disk-backed repository tests retain General Task ID/assignee/job/due/reminder after Done/retry/restart and compare financial records unchanged. Existing Chris 12h/$480, paid historical work, task dates/assignments, invoices, receipts and recurring regressions remain in the suite.
- Native CI instrumentation invokes the plugin inside each actual APK with the request captured from production LocalTaskReminders. It checks dynamic drawable lookup, initialize, same-ID scheduling twice, one pending alarm, offline delivery with the correct small icon, and cancellation. Test instrumentation is never included in the delivered APK and does not access the shop database.
- Release gate requires clean analysis/full regressions, enabled regular navigation, Android debug reminder proof, iOS compilation, and install-over from b4656 preserving UID, original tables, receipt attachment and Force Offline state through restart. Final signed APK certificate/package/version are independently checked after download.

## Visual comparison and limits

Before/after comparison uses supplied Owner screenshots and actual Flutter widgets with synthetic fixtures. Existing weekly controls and payment authorization flow are retained despite their omission from the illustrative compact-card mockup. Native typography and factual records remain authoritative; gallery overlays are excluded. Employee comparison demonstrates the real row component; surrounding test-shell header is illustrative, not a redesign of Employees navigation.

Physical Owner-phone installation/touch approval remains with the Owner. Previously deferred cross-device/assigned-employee reminders and end-to-end iPhone notification delivery remain deferred. Final commit, build, run IDs and pass counts are recorded in the delivered release checklist and issue #455 after verification.
