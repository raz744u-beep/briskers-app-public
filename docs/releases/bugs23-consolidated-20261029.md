# Briskers Bugs 23 — consolidated Android candidate (2026-10-29)

## Base and safety
- Derived from the most recent normal S26 source branch `fix/b2489-appointment-date-selection-20261029`; preserves the existing signed app identity and production package.
- No Owner Delete v3, separate Tasks/Payroll TEST experiments, data migration, posted payments or job-status redesign in this APK candidate.
- Do not mark release ready until exact-head GitHub Diagnostics, iOS compile and the Android signing/verification run all pass. Installation requires owner S26 acceptance.

## Included candidate fixes
- Appointment date: existing b2489 visible Type date fallback, calendar entry, and same selected date with preserved time.
- Invoice catalogue: existing item categories from shop-scoped local snapshot in Force Offline; in Auto refresh bounded to 4 seconds with offline fallback; never pass empty categories by construction; old item catalog category labels are fallback.
- Notes: cached standard-note picker opens before Auto remote read, remote refresh renders nonblocking; payment button starts visible spinner and debounce guard while payment method RPC loads, bounded timeout.
- Email/PDF: no issue-document RPC if a numbered invoice is already known, so stale draft indicator cannot force another issuance; on transport failure owner may explicitly use cached PDF after reviewing that it's potentially stale. Actual payment/close state unchanged.
- Vehicle Invoice Repair History: each customer vehicle has a Repair History action; records filter by stable vehicle id; description comes from cached invoice line items/memo, search within that vehicle by any description term/number/date, including imported invoice details when cached, with original invoice tap. No inferred jobs, no rewriting MobileBiz data.

## Not yet verified / separate
- Invoice Miles Out editing was reported broken; original branch already contains separate Miles Out editor + durable queue. This behavior still requires device acceptance; cannot mark repaired based only on code.
- Existing b2489 long-press guidance, invoice status updates and other earlier fixes are inherited, not reimplemented.
- Owner Delete v3 and full Tasks/Payroll/status redesign are separate gated tests and intentionally excluded.
- Full historic invoice search requires locally cached detail snapshots. If older imported details are missing/offline, do not claim completeness or silently attach ambiguous vehicle data.

## Manual S26 verification
1. Appointment date on November day via calendar and Type date.
2. Open #6340 Auto Send → Email and Preview with online available/unavailable; verify email address, amounts and attachment, no unexpected RPC re-issue.
3. Invoice → Add catalog item: list of existing categories Auto and Force Offline; save item and ensure category reappears.
4. Invoice #6357 Add Standard Note: picker opens promptly, select template and ensure note saved to invoice/PDF.
5. Pending-sync invoice Add Payment: opening spinner shown, no double dialogs; **do not use a real customer payment to test duplicates**.
6. Invoice Miles Out pencil: edit and reopen; independent of Job Miles In and visible on PDF; if fails, block acceptance.
7. Raymond Taylor → Vehicles → Repair History: select one vehicle, search 'speed', verify invoice original date/description and no other vehicles; MobileBiz closed records when cached.
8. Check Expenses, Jobs, dashboard, customer selection and offline first-frame speed for regressions.
