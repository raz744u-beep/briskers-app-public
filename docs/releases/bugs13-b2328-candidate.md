# Briskers Bugs 13 consolidated Android candidate — release acceptance

**Baseline:** owner-installed v0.10.9 build 2327 (modern shell/dock), not outdated main.
**Purpose:** one stability/accuracy update. This is a **QA candidate**, not owner-approved production release. No production database change, no outbox clearing, no direct payment mutation, no paid resource.

## Included in this branch (source-level; require exact CI and phone checks)
- [x] PR #259 — invoice payment receipts load before historical archive, first transaction page visible before cache work, stale search/cache doesn't replace newly confirmed receipt.
- [x] PR #259 — Invoice Detail → Expenses monetary amount styling matches main Expenses (17.5sp/w900, correct red/green).
- [x] PR #260 — 30/90/365 day or other selected period totals read all posted, permission-checked transaction pages, exclude projected receipts from sums and don't display misleading first-page totals; show Calculating/Unavailable when incomplete.
- [x] PR #260 — saved invoice odometer displayed in Invoice Notes once without copying into editable memo; PDF already prints header mileage.
- [x] PR #262 — Edit Customer/Save Vehicle use approved dark blue token, customer create and other module Save colors preserved.
- [x] PR #256 forward-port — Today/Upcoming/Past/All one row; Today includes all current-day appointment statuses; filter changes only local query, no unneeded network pull. Historic `confirmed_today` remains internally supported.
- [x] Jobs — initial cached job cards paint before slower secondary count/status searches; quarantine/retirement visibility guard preserved. Cached-first Auto mode no longer displays a false offline banner; real Force Offline or sync failure shows truthful notice.
- [x] Expenses — rows returned by server transaction pages explicitly establish cloud confirmation; cached/unknown stays unknown, pending/failed still takes precedence. Does not fabricate `sync_state` or write financial records.

## Still requires completion/verification (DO NOT silently mark accepted)
- [ ] Latest exact-head Flutter analyzer, regression suite, and iOS compile checks.
- [ ] Signed Android artifact with expected Briskers package and permanent certificate; increment versionCode over build 2327.
- [ ] Samsung install-over without uninstall or clearing local data. Check startup, existing jobs/invoices, correct colorful bottom nav.
- [ ] 30 days vs 1 year total differences checked against permission-scoped server transaction totals; long-history and warranty processor fees.
- [ ] Fresh posted payment visible promptly in Expenses & Income, including search by invoice; verify no duplicate income.
- [ ] Customer Save dark blue, Invoice Expenses amount readable, Notes mileage after edit/reopen and PDF.
- [ ] Four appointment tabs fit on Samsung; no lost local pending check-ins.
- [ ] Jobs cold/warm switching and cached-first banner; Expense neutral/confirmed cloud indicators. Time and record failures.
- [ ] Owner confirms.

## Not included — carried forward in master #45
- [ ] Owner Delete Job #116, protected orphan appointment #114 cleanup #239; maintain J-19/#6346, do not delete any real records.
- [ ] Production task/nickname/weekly payroll, editable Work Log and advanced navigation. Isolated offline Tasks TEST PR #258 remains a separate APK with distinct Android package.
- [ ] App-wide action-color audit beyond targeted Customer/Vehicle correction #261.
- [ ] ExpenseIQ 120 photo errors, unresolved intermittent slow expense detail, sync scope `job_retirements_v2`, backup/restore and iOS physical device parity.
- [ ] No claims that every remaining Jobs hiccup or Expenses sync icon is fixed without phone validation.

## Release policy
After each signed APK, update master #45 with source SHA, build version, CI links, artifact and device acceptance/deferrals. Never mark a code-only checkbox shipped. Avoid stale `main`, no paid resources or production database changes.
