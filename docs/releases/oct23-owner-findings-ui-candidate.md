# Oct 23 Owner Review Candidate — pre-release manifest

**Track:** Signed normal Briskers Android build candidate; install-over only, do not uninstall, reset or clear data.
**Base:** tested b2391 branch `fix/post-b2382-ux-polish-20261021`; feature branch `fix/oct23-owner-findings-ui-batch-20261023`; PR #310.
**CI/App signing:** Not claimed until exact-head Diagnostics, iOS and Android-signature verification succeed.

## Included in this branch (coded, NOT yet phone-accepted)
- #292 Jobs filter header right-align the Total count.
- #303 Customers search right-side clear X, immediate local search, invalidating stale requests. Jobs, Appointments, Documents and Expenses already have clear X.
- #243 Invoice Findings sheet returns a requested action, awaits add/edit/resolve, then targeted findings-only refresh; no full invoice reload for new finding operations, and no premature sheet-close refresh race.
- #309 Job Findings now has a same-vehicle repair-Job chooser with explicit historical-repair confirmation; does not implicitly resolve on viewing Job J-7. Solid surface and outlined card for readable text. Reject additional resolve attempts when a prior finding action has a known error; outbox is preserved.
- #261 Expenses Account dialog semantic-red action/focus; Quick Transaction expense-red vs income-green modal theme and Save; title-case shortcut name on Save, preserving acronym casing.
- Expense Entry date picker semantic red/green accents based on selected direction.

## NOT included / NOT fixed by this build
- Existing blocked `finding_action` #182/#183 on Owner phone: **NO local outbox cancellation, replay bypass, false sync success, or server writes**. It requires independently verified reconciliation and an explicit user-approved recovery. Server finding remains OPEN until safely resolved.
- #308 persistent per-user left/right floating create-button preference across modules (design approved; do not claim).
- #302 compact editable Mileage In / Out invoice header and PDF (design approved; do not claim).
- #301 larger Customer Service History/Work Performed/Visits redesign, still awaiting Owner review.
- #116 backend Owner Delete, isolated sandbox, no permission release.
- #297 payroll/payment methods, separate Dot PR #306.
- #293 customer payment category patch, not deployed.

## Required acceptance
1. Exact-head Flutter Diagnostics and iOS compile pass.
2. Signed Android APK generated with `com.briskers.briskers_app` and permanent certificate SHA-256 `82075a34ef748541a270af4172dd3ddc37f3e464d9ac9f20eeef7f40a029ff08`.
3. Samsung install OVER b2387, preserve data, verify Jobs count alignment and search X; Expense dialog red/green/name formatting; invoice Findings add/resolve banner; choose historical repairing job and confirm without altering real data in tests.
4. **Do not tap Resolve again on the real stuck DME finding until #182/#183 reconciliation is separately approved.**
5. Cross-device/offline regression before merge or broad release.
