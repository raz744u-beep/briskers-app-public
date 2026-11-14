# Bugs 36 consolidated handoff — November 14

Continues verified build 4651 / commit 89ee89d44416de8a1404d3cf6bba1690633538a7 on the existing release branch and issue #455. Uses the Owner's `Briskers_Bugs36_Designs_and_Fixes_Handoff(1).zip`. Illustrative records are never imported into the shop database.

## Included corrections

- Job Detail reload and background Job sync preserve pending/conflicted local core edits, including customer/vehicle identity, VIN, title and hours. Customer-only bundles do not erase vehicle links; orphan cleanup retains vehicles referenced by jobs/findings. Navigating across all four customer tabs and back creates no edit/outbox operation.
- Customer Overview opens Service History. Compact two-line visit headers have independently tappable neutral Job/Invoice links; body tap expands literal completed repairs and separately labels invoice work whose completion is unconfirmed. Newest first, search includes collapsed repair/part descriptions, dates and invoice numbers, and vehicle filtering stays local. Includes invoice-only history without inventing jobs. Partial mechanic completion is not presented as an entirely completed repair. No payroll/private cost details are displayed.
- One fixed `+ New` action across Overview/Info/Vehicles/Notes, with bottom scrolling clearance and the existing executable customer-context actions. Removes top duplicate controls and the disabled messaging placeholder.
- Approved white compact shared cards retain status borders/badges, assignment hours, progress, invoice links, expansion and long press.
- New Service Task starts Open and unpaid, with priority, dates and mechanics/hours. New-task Work Status and Needs Review choices are removed; an explicit Already paid / historical work checkbox retains the existing confirmation and wage protections. Existing-task editing remains available.
- Findings present Unresolved / Resolved / Not Applicable. Add to Job immediately displays Resolved on this job; removing it restores Unresolved. Not Applicable requires explicit confirmation, preserves original text and optionally appends a labeled note, excludes it from unresolved counts/invoice notes, and remains reopenable in vehicle history. One durable local action is verified before replay; lost responses do not send duplicate mutations.

## Data and synchronization

No local schema migration or production customer/task/payment rewrite is performed. Existing Bugs 36 assignment corrections, date inheritance/manual overrides, historical cutoff, payroll protections, invoice closing/finalization and Cintas recurrence remain in place.

The additive server migration only expands the finding-state constraint and installs a narrowly scoped disposition RPC. It performs no backfill. The API wrapper is authenticated-only; the private implementation checks authentication, business edit permission, finding ownership/scope and the original body under a row lock. Existing body changes produce a conflict instead of being overwritten. Repeated identical requests return without another row update. Public/anonymous execution is revoked; fixed empty search paths are used. The additional authenticated security-definer advisory is expected for this permission-checked RPC; no new anonymous endpoint is exposed.

## Verification

- SQLite tests: pending vehicle correction vs repeated stale pulls, no-edit customer navigation, history search/filter/reopen, whole-task completion, unpaid/paid reassignment, inheritance/manual overrides, financial and recurrence preservation.
- Phone-sized Flutter widget tests: actual route navigation, independent history links, compact cards, service/general tap vs long press, filters and keyboard/system-navigation clearance, editing Done tasks and explicit Not Applicable confirmation.
- SQL disposition checks ran only in the disposable synthetic sandbox, with rollback: authentication, tenant boundary, retained original body, optional note, idempotent retry, reopening and stale-edit rejection. Deployed RPC/privileges were inspected read-only; production records were not used as test fixtures.
- Release gate requires exact-head Diagnostics and iOS compilation. Android upgrade validation uses the original permanent certificate and latest verified build 4651 as the immediate predecessor, with `adb install -r`, offline restart and record/photo preservation checks. Final run IDs, signature, digest and APK are recorded in delivery evidence after those checks finish.

## Explicit limits

No direct access to the Owner's Galaxy database. The original reported vehicle loss cannot be forensically distinguished between persisted/view state on that device; the reproducible stale-refresh vulnerabilities are corrected and synthetic navigation/persistence checks cover both local storage and display. This release does not guess or repair a vehicle ID already missing from existing data.

Cross-device/assignee reminders on Android and iPhone and grouped multi-item finding estimates remain deferred as allowed in the handoff. Existing General Tasks/reminders are preserved. On-device Owner acceptance is separate from emulator install-over and phone-sized widget validation.
