# PR #444 final release review

Review checkpoint: source `72e87e0d6acfa1a3ea0ff7a1d1c87d9e8ef26bf1`, plus the Job progress empty-state/tap correction in this commit. Branch: `fix/bugs31-payroll-navigation-noop-auth-20261106`.

**Release held. No new APK built or certified by this review.** The Owner's latest instruction postpones #445: no second app, staging environment, production data changes, payment changes, or historical balance reconstruction.

## Status definitions

Present means inspected in source, not demonstrated on a phone. A test file is coverage, not a passing result. Existing successful workflows for earlier commits are not final-commit certification. Actual Owner-uploaded visual references have not all been rendered alongside the final app in this review; the approval descriptions and repository parity audit were used. Complete screenshot parity remains unverified.

## Release blockers

1. **Unknown-date historical invoice eligibility.** `LocalInvoiceTaskStore.save` skips invoices only when `document_date` is non-null and before `2026-11-07`; a null date continues into task creation and inheritance. `LocalPayrollRepository.work` marks historical labor through `d.document_date < cutover`, which also does not classify null dates as historical. This is a source-level eligibility gap, not proof that a particular real payment has been duplicated. Before releasing, test undated archived invoices and establish trustworthy new-work provenance or require explicit Owner-reviewed carry-forward. Never infer new unpaid debt from the lack of a new-ledger payment.
2. **Older employee payment provenance/display remains unverified.** `history(employee)` reads `regular_payroll_payments`; `historyWithWork` decorates that same ledger. This review did not establish a verified mapping from older expense/payment records to immutable employee IDs and their Reports presentation. This does not mean the old records were deleted. Do not copy amounts into the new ledger, infer matches from names, or manufacture balances. Audit the actual historical source read-only and demonstrate preservation/display without new payable credits.
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
| Historical payroll cutover and legacy payments | Dated pre-cutover guard, archived flag and explicit reviewed carry exist | **Blocked:** unknown dates and legacy payment provenance above |
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
