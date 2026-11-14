# November 14 final Work & Payroll handoff

Baseline: b4659, bd75df2bca2177767d07004151a83835d031d190. Current tracked checkout was reconciled to this existing branch; no concurrent tracked edits found. Source: attached README_START_HERE.md and IMAGE_INDEX.md, all 28 images inspected. Latest written decisions override illustrations. Implementation is NOT Owner Approved.

| Requirement | Baseline reconciliation | Source / verification plan |
|---|---|---|
| A Separate Work/Payroll/Reports/Taxes & 1099 tabs; only selected colored | Selected color/routing already correct; labels and icons need change | approved_tasks_ui.dart; tab/navigation widget tests |
| A Work compact week selector, individual assigned tasks, read-only weekly labor | Needs change: banner and job summaries still present; weekly filtering already works | employee_work_review.dart, owner_payroll_screen.dart; exact-task/back/week, date-filter tests and rendered references 18/19/28 |
| A Truthful selected-week payroll summary | Needs change: use saved draft/payment state only; no estimates from assigned hours | Work summary read-only projection; no-draft/draft/paid/past/future tests |
| B Per-mechanic Total/Paid/Remaining and real payment history | Needs change; existing coverage and history available | approved_task_details.dart, local_payroll_repository.dart; two-mechanic partial coverage and historical-paid cases; ref 20 |
| B Blue circular-arrow In Progress icon | Needs change | shared task status icon, Work summary; ref 18/20 |
| C Compact Payroll rows, expansion, View Task, independent checkbox/job link, saved state | Already correct; retain and style expanded actions, remove no working functionality | weekly_labor_review_screen.dart; existing nov14_quick_fixes_ui_test.dart + ref 21 |
| C Large Payroll Status banner | Already absent in current profile Payroll | owner_payroll_screen.dart, weekly_labor_review_screen.dart; assert absence |
| C Explicit partial In Progress selection/payment | Needs change: current UI and payment guard require Done. Extend existing minute/coverage/authorization path only; no replacement engine, rate/rounding change or data migration | local_payroll_repository.dart + WeeklyLaborReview; offline 20/8/12, idempotency, second mechanic, finish after payment, historic cutoff |
| D Edit Payable Hours dialog, decimal input, nonnegative/remaining validation, draft only | Needs redesign; current editor title is Edit Mechanic Labor | payroll dialog widgets; ref 22 without arrows; fractional/cancel/zero/over-limit/draft tests |
| E Adjustments & Repayment popup | Needs compact layout; existing arithmetic/limits/reason requirements retained | weekly_labor_review_screen.dart; ref16, keyboard/safe-area/draft-only tests |
| F Historical Expense Review | Needs compact currency/date/cards/search layout and truthful field matching | historical_expense_review.dart; ref17, unrelated-payee exclusion/read-only/offline tests |
| G Two-line employee list | Already correct; unchanged | employee_list_tile.dart, existing width/permissions tests |
| H Android icon / completion persistence | Already corrected and debug/signed-release verified in b4659; preserve | local_task_reminders.dart, existing native probe and persistence tests |
| I Approved logo v3 artwork | BLOCKED: archive contains references, no original approved asset; leave existing artwork unchanged | No logo regeneration or mockup extraction |

No live records are used or edited for tests. No invoice/expense/payment history migrations. Physical phone visual/touch approval remains pending until Owner inspection. New renders and final commit/build/evidence will be added after verification, before release.

## Implementation and pre-build visual review

A–F are implemented in the existing widgets/repository. G (two-line Employees) and H (notification icon and durable Done/All General Tasks) retain the verified b4659 implementation. I remains blocked: no original logo #3 asset was supplied. There is no new payroll table, assignment/task copy, invoice change, or financial-history rewrite. The existing paid-work trigger is replaced atomically with a scoped guard allowing only explicit completion of the new In Progress payment class at unchanged assigned hours; prior paid records and all payment/coverage rows remain immutable.

| ID | Delivered behavior | Verification |
|---|---|---|
| A1 | Separate Work / Payroll / Reports / Taxes & 1099; only selected tab colored | Tab routing/color and equal touch-region tests; profile lifecycle tests |
| A2 | Compact light-blue week selector; no Work Review banner | Render `final-work-overview`; week navigation/filter tests |
| A3 | Currently Assigned Tasks; exact task navigation; employee/week retained | Work callback test plus actual enabled app navigation test |
| A4 | Green weekly labor card with clipboard and blue circular-arrow In Progress; read-only task cards | Actual assigned-minute fixtures and work-date regression tests |
| A5 | Payroll This Week uses saved draft or selected-week authorized payments; otherwise Not calculated | No-draft, saved 8h draft, prior-week actual $320, future-week no fabricated total tests |
| A6 | No combined tab or repeated ongoing-job breakdown | Source/render comparison with written superseding decisions |
| B1 | Per-mechanic Total/Paid/Remaining tiles; real last payment and history | Synthetic Chris 20/8/12 and separate Kam 5/0/5; two payments retained after restart |
| B2 | Paying In Progress hours never completes work; explicit Finish / Mark Done / Mark All Done still work | Offline SQLite, LAN receipt, canonical Owner ledger, bulk-completion and immutable-history checks |
| C1 | Compact individual payroll rows, selection, real descriptions, expansion | Existing compact navigation/selection/scroll test retained |
| C2 | Expanded actions only View Task / Payable Hours; no Edit Task or Payroll Status banner | Render `final-payroll-expanded`; exact saved-task navigation test |
| C3 | Explicit In Progress partial payment; remaining balance available for later explicit selection | 8h/$320 then 12h/$480; stale request rejected, exact operation replay returns no-op; employee balances independent |
| D1 | Edit Payable Hours: plain decimals, no arrows, Total/Paid/Remaining | 1.25 / 3.60 / 8.75 / 0 accepted; negative/over-limit/third decimal/NaN rejected |
| D2 | Save affects only selected-week draft; no assignment/status/payment mutation | Draft callback and persisted SQLite draft tests; original assignment remains 20h |
| E1 | Compact Adjustments & Repayment; actual advance balance, separate labels, total, Cancel/Apply | Render `final-adjustments`; $400 + $20 − $50 = $370 existing regression; keyboard inset checks |
| E2 | Apply persists draft only; existing authorization, advances and repayments retained | No authorization callback on Apply; actual existing payment/advance/restart workflow tests |
| F1 | Compact historical search/cards; currency cents/date; original details and transaction ID | Render `final-historical-expenses`; actual-field matching excludes unrelated Worldpac; permission-revocation/read-only tests |
| F2 | Historical cutoff and offline original records unchanged | Existing historical/payroll/date/financial preservation tests |
| G | Compact two-line Employees and saved compensation unchanged | Existing 360/412-width employee-row and permissions test rerun |
| H | Existing valid notification icon and completed General Task persistence unchanged | Existing Done/All/restart tests; native Android probe runs on signed candidate |
| I | Logo replacement BLOCKED; existing production artwork retained | Archive/reference inspection; no artwork generation or extraction |

Visual differences from illustrative references, reported before the signed build:
- Final written decisions replace Assigned Jobs with individual Currently Assigned Tasks, keep separate tabs, remove the duplicate breakdown and decimal steppers, and retain View Task / Payable Hours.
- Test screenshots use explicitly synthetic data. No illustrative 18h, 21h/$840, 33h/$1320, hypothetical payment, customer vehicle or expense category is copied into production records.
- Actual production logo is unchanged; replacement with missing original #3 remains blocked.
- Native Flutter font metrics and accessible controls are retained. Long content and multiple mechanics scroll; keyboard-safe dialogs keep their actions reachable. This is a visual comparison, not Owner approval or a claim of pixel identity.

The final APK remains **awaiting Owner inspection**. Build/signature/install-over results are to be added to the delivery checklist after the artifact exists.

## Pre-build checks completed

- Full Flutter regression suite: **1,672 passed, 3 skipped**.
- Enabled regular-app invoice → mechanic → task → Employee Payroll → Reports navigation: **1 passed** with `BRISKERS_ENABLE_OWNER_PAYROLL=true`.
- `flutter analyze --no-pub`: **No issues found**.
- `git diff --check`: clean.
- Six actual widget renders reviewed against refs 16–22 and latest written overrides before release. Synthetic 412×915 logical viewport, 32-pixel bottom safe area; keyboard inset tested.
- Signed Android compilation, native notification probe, iOS compilation and actual emulator install-over evidence remain release gates, not completed claims in this source document.
