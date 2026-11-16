# Approved seven-screen batch

Baseline: delivered build 4665, commit `5a3a3c7b7e98c8e5c76dcf7cec72128c96b37294` (includes PR 456).
Authority: `Briskers_NEXT_Approved_Screens_Work_Handoff_UPDATED_7_Visuals_NO_LOGO.zip`, its START HERE instructions and mockup index. Four final mockups plus three before-state references. No branding assets changed.

## Changes

- Sectioned Employee Details reads authorized encrypted local records first. Explicit offline edits retain their comparison baseline, survive refresh, and sync through an Owner-only compare-and-set endpoint. Missing local profiles cannot blank server records. Conflicts require an explicit reviewed choice; authorization loss clears protected UI. Full SSN is never accepted by this cache or sync endpoint. W-9/default payment method remain unknown unless actually provided. Local compensation remains available without a complete private profile.
- Compact payment summary, highlighted payment total, adjustment action, zero-balance advances collapsed by default, retained original debt editor and repayment history.
- Navy Verify Payment dialog with directly editable final gross, using the existing payment arithmetic, authorization and ledger write path.
- Customer-first collapsed history cards use the shared task surface, recorded allocations, original record links and gross/debt/net totals. A saved $560 settlement is not recalculated from a $490 labor allocation.
- Compact blue/green/purple payroll metrics; Taxes naming with gray selected stripe; empty assignments collapsed with defaults reset per employee/week.

## Verification and release

`test/nov14_seven_approved_screens_test.dart` exercises production widgets with synthetic records: offline private profile edit/access revocation, cache races and conflict choices, exact editable-gross arithmetic, recorded history and all three links, empty/nonempty assignments and manual toggle, advances/history and Taxes. Standard and smaller viewports are captured.

`integration_test/approved_screens_test.dart` runs those same production widgets on an Android emulator, with a separate `com.briskers.qa` application identity. The driver exports actual Android-rendered PNGs for comparison. This test-only entry point and synthetic data are not used by `lib/main.dart` or the release APK. Review these renders before promoting the source to the signed release branch.

`tools/tests/customer_payment_category/employee-details.mjs` checks the actual SQL endpoint against isolated PostgreSQL: Owner-only access, explicit baselines, concurrent changes, retry idempotency, protected-field rejection, and contact edits without compensation-history writes. The additive endpoint is deployed without altering employee or financial records. Its intentional authenticated SECURITY DEFINER access is guarded internally by active shop Owner membership and `settings.manage`; PUBLIC/anon execution is revoked.

The release workflow still requires exact-source diagnostics/iOS and the existing financial/offline regression gates. Signature verification uses the existing permanent certificate. Android install-over testing now includes the exact delivered build 4665 APK, SHA-256 `980fbd4e9d04a8879f52652bdd46cd8e9c878291c2b31cadec451a87a0768a77`, with preserved database and receipt-file evidence. Version code must exceed 4665.
