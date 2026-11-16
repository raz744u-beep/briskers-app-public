# PR #444 final release review

Development branch `fix/bugs31-payroll-navigation-noop-auth-20261106`. This checklist records the feature audit and the outstanding evidence before release.

**Release held. No new APK built or certified by this review.** The Owner's latest instruction postpones #445: no second app, staging environment, production data changes, payment changes, or historical balance reconstruction.

## Status definitions

Present means inspected in source, not demonstrated on a phone. A test file is coverage, not a passing result. Existing successful workflows for earlier commits are not final-commit certification. Actual Owner-uploaded visual references have not all been rendered alongside the final app in this review; the approval descriptions and repository parity audit were used. Complete screenshot parity remains unverified.

## Release blockers

1. **Historical invoice eligibility.** The projection now requires a valid business date on or after November 7. Archived and undated invoice portions are excluded from ordinary weekly settlement unless the Owner explicitly confirms an unpaid carry-forward for the individual allocation. Source-level and fixture changes are on this branch. Final exact-head tests are listed in the delivery checklist.
2. **Older employee payment identity remains unresolved.** A read-only catalog and aggregate audit found no employee ID column on historical financial transactions and zero records in the payroll allocation bridge. Searching payroll-related category names identified 664 transaction candidates before November 7. Of those, 207 matched exactly one current employee name by payee/vendor text and 457 matched none. Category and name alone do not establish who was paid, and the count does not establish 664 wages. Employee Reports reads the regular payroll ledger by immutable employee ID. Its historical expense review now searches original transaction IDs, amounts, dates, payees and remarks in a separate read-only view, including cached records in Force Offline. A name is only a search term. Unlinked records remain unattributed and cannot contribute to pay or balances. Reconstructing employee identity for individual unlinked transactions still requires independent documentary evidence.
3. **Final visual/runtime and signed install-over evidence incomplete.** Current CI was still running at the last inspection, and subsequent source changes require fresh exact-head results. Package and certificate constants alone are not proof about an APK. Final screenshots, signed binary inspection, and emulator retention evidence must be attached before delivery.

## Inclusion and verification checklist

| Approved area | Inspected implementation / evidence | Verification still required |
| --- | --- | --- |
| Job customer/vehicle, mileage, financial status, original tiles | Existing Job Detail sections retained; scoped progress added | Full-page visual comparison and each tile on final source/phone |
| Native invoice chip, teal, exact invoice route | Job Detail ActionChip and invoice route; regular navigation widget covers actual document ID | Final rendered geometry; no/multiple invoices; physical tap |
| Job progress, distinct service tasks and split completion | `JobTaskSummary.progress` counts task IDs and requires all portions Done; includes source-backed rechecks and job General Tasks | 0/4, 2/4, all Done, rechecks, inactive/void sources and cross-shop scope |
| Empty task state and progress tap | This commit shows `No tasks yet`, omits empty percentage bar, and makes progress area open scoped Tasks | Fresh analyzer/widget verification and phone |
| Matched Main Mechanic / teal Job Tasks controls | Dedicated Job controls; task route uses same workspace with job scope | Samsung widths, keyboard, back navigation |
| Work Completed collapsed; New clear of tiles | Existing collapsed section; regular navigation test checks viewport vs FAB | Final screenshot and phone scroll through all tiles |
| Global and Job-scoped Tasks | Same `TasksWorkspace`; scoped Service/General lists and creation actions; `bugs32_scoped_tasks_test` | Fresh exact-head pass, restart, correct job return |
| Collapsed groups/details | Empty expanded-job set; expansion tiles default collapsed | Both paths, General Tasks and navigation/reopen |
| Labor Task / General Task creation | Invoice-linked service workflow and job-linked non-billed general records | Locked/finalized invoices, offline restart, real UI actions |
| One labor pencil / Manage Labor Assignments | Invoice and workspace route to focused manager; duplicate Assign/split removed | Actual tap/add/replace/remove and error feedback at Samsung width |
| Add second mechanic preserves first | Add path no longer retires inherited allocation; synthetic integration coverage | Fresh tests; persistence across restart; independent completion |
| Assigned hours vs customer billing | Separate estimates/credits; add-second starts at zero; manual overrides retained | Editing one allocation leaves billing and other labor unchanged |
| Assignment dialog | Spaced fields, select-all decimal entry, teal Save, Cancel; no steppers | Keyboard/insets, accessibility, final screenshot |
| Started-work reassignment | `72e87e0` permits reassignment only before earned/paid time; guarded immutable paid work | Fresh integration and UI failure/lock feedback |
| Start / Mark Done | Saved positive assigned hours used once; no actual/credited dialogs; paid guard remains | Independent mechanics, zero hours, retry, real UI |
| Jobs list display-only | Quick mechanic/hour edit handlers removed; `JobTaskSummary.hours` projects assignments | Split totals, immediate refresh, no allocation vs unavailable, legacy values untouched |
| Job menu cleanup | Duplicate Owner assignment entry hidden with payroll enabled; mechanic labor access retained | All roles, Delete safeguards, no hidden edit path |
| Offline profitability | Compact unavailable state retained instead of fabricated zero totals | Actual cache/no-cache rendering and Owner-only access |
| Original Tasks TEST roster/profile | Restored PayrollOverview, four tabs, Details, weekly labor review, history and Taxes placeholder | Side-by-side final rendering against all original reference states |
| Offline employee pay settings | `saveLocalPayBasis`; explicit local-only editing using Owner session | Rate/type save/restart; historical paid rates unchanged |
| Payroll partial payments/advances/repayments | Existing ledger, coverage, history and fencing retained | Exact-head enabled tests, retry/restart, cross-device physical Wi-Fi |
| Single Owner login | Session-based grant used by task/payment paths; identity/role validation retained | Zero extra prompts, sign-out/switch, Secretary denial on final binary |
| Historical payroll cutover and legacy payments | Dated pre-cutover guard, archived flag and explicit reviewed carry exist | Verify exact-head cutover regression; original legacy payment linkage remains blocked |
| Receipts and original pictures | Independent HTTPS gateway, consent/review/manual fallback, SAF/cached-photo recovery retained | Real gateway with Force Offline; save/restart; original folder grant on phone |
| Expense totals/payment statuses | Partial local subtotal explicitly labeled; Paid/Partial/Recorded separate from cloud state | Dates/filters/local edit/delete/recurring, no duplicate income |
| Offline recurring | Existing offline repository, occurrence IDs and recurrence suites retained | Create/edit/stop/generate/restart, duplicate replay and Cintas phone acceptance |
| Invoice corrections | Inline teal mechanic labels, separate billed hours, document/PDF mileage suites retained | Final PDF/rendered invoice/customer/VIN/plate/totals comparison |
| Offline jobs/estimates/invoices/payments | Existing drafts, numbering, conversion, payments and outbox paths retained | Fresh complete suite and phone creation/cash/restart/replay |
| Number reuse / delete | Existing numbering pools and guarded delete v3 retained | Owner vs Secretary, released job/invoice number reuse on phone |
| LAN and Supabase reliability | Existing enrollment, fencing, retry policies and retry-storm workflow retained | Exact final-head result, physical mixed devices, real service availability |
| iOS parity | Shared Flutter source, existing iOS compile workflow | Exact-head compile and actual iOS behavior |
| Package and permanent signing | Workflow requires `com.briskers.briskers_app`; expected certificate SHA-256 `82075a34ef748541a270af4172dd3ddc37f3e464d9ac9f20eeef7f40a029ff08` | Inspect final signed APK; monotonic version; never uninstall/clear data |
| Safe install-over | Workflow configured for b2568 plus current b2582 intermediate and SQLite/preferences/photo/outbox retention | Successful final-run retention evidence; actual Owner phone remains separate |

## Checks actually executed in this review

- Candidate-check Python suite: 41 passed.
- APK certificate parser Python suite: 10 passed. This tests the parser, not a new APK certificate.
- UI placeholder audit: 92 screens, passed. This is not functional or visual acceptance.
- `git diff --check`: passed for the progress correction.
- At checkpoint `72e87e0`, retry-storm run `42443460792` and Gloria run `42443460751` succeeded; Diagnostics `42443460772`, iOS `42443460755`, and Android recovery `42443460754` were still running. These do not certify this follow-up commit.
- Local Flutter startup was rejected by automatic approval review because it attempted a cloud metadata endpoint. It was not retried or bypassed. Use the existing GitHub CI for unaffected verification; no local Flutter pass is claimed.

## Required next release evidence

Resolve the historical eligibility/provenance blockers using controlled synthetic records and read-only historical evidence. Run fresh exact-head diagnostics and enabled production-screen navigation, inspect actual rendered screenshots against the Owner references, and verify preserved modules. Then run the existing signed Android workflow once on this branch with `payroll_candidate=true`, inspect the binary identity/certificate/hash and successful install-over retention evidence, and deliver one APK with this matrix updated. Physical-phone-only checks must remain labeled pending. Do not relabel the older b2582 or another earlier artifact as the requested release.


## Rendered-screen review

The approved full-page teal Job reference was compared with a 390-pixel rendering of the actual regular app using a synthetic job. The first capture showed two original invoice labor lines, three completed allocations, and one complete task, correctly yielding 50%. It exposed a chip alignment discrepancy and a different unit in the Work Completed subtitle. Both were corrected in source. The captured global Tasks view had its job group collapsed. The rendered payroll roster, unpaid employee tasks, paid employee tasks and separate Reports history were inspected. The original Tasks TEST and regular app both describe the Taxes and 1099 tab as a placeholder. No filing or tax computation is claimed.
