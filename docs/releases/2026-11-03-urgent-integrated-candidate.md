# Urgent integrated shop candidate — not released

Source branch: `integration/urgent-shop-completion-20261103`.
Baseline Bugs 26: `9867eee0f7124e8ade79f7a6337697b6640e200c`.
Approved summary source: PR #417, `229667563ada3a87f92ef93eac1ffb447fcb373f`.

## Scope and evidence

| Work | Coded | Tests | Release status |
| --- | --- | --- | --- |
| Existing Bugs 26 fixes | Preserved from integration head | Exact combined-head CI required | Unreleased |
| Compact invoice/estimate summary | Combined from #417 | Existing widget tests | Unreleased |
| Independent receipt AI client | HTTPS, secure-storage device token, consent, explicit editable review, bounded upload/response/timeouts, no redirect or Supabase fallback | Transport tests added; CI pending | Gateway deployment and real receipt acceptance blocked |
| Reviewed receipt amount | Printed total final; no automatic vendor surcharge after payee/template selection | Review and integration regressions required | Unreleased |
| Receipt expense persistence | Selectively reused #415 atomic local transaction, original photo, structured receipt projection, deferred sync | SQLite close/reopen and duplicate-photo regression added | CI pending |
| Quick / Full Manual | Existing paths retained; missing AI configuration leaves attached photo available | Existing transaction regressions and full CI required | Unreleased |
| Tasks / Payroll | Existing work remains separate on `integration/tasks-payroll-local-persistence-20261102` at `371296d1` | Prior isolated test evidence only | NOT integrated into regular app |
| J-18 and missing photos | Existing read-only audit/display improvements retained | Exact local IDs and attachment mapping need phone evidence | Unresolved; do not mutate financial records |

## Receipt deployment contract

The client reads public `BRISKERS_RECEIPT_AI_GATEWAY_URL` build configuration and a
revocable, gateway-issued shop/device token from platform secure storage under
`receipt_ai_gateway_token:<businessId>`. No provider key belongs in the APK.
The independent service must authenticate and authorize the device/shop/role,
limit requests, store the provider secret server-side, and avoid receipt logs or
retention. Neither that service nor device enrollment exists in this repository.
Missing configuration fails immediately to existing manual entry. Do not claim
internet AI operational or build a shop update with this incomplete setup.

No Supabase synchronization was enabled, backend deployed, financial record
changed, device storage cleared, or regular APK produced by this work.

## Release gates still open

- Exact combined commit: analyzer, full Flutter tests, iOS compile, Android compile.
- Real independent gateway deployment/enrollment and receipt acceptance with
  Supabase unavailable; token revocation, authorization and limits verified.
- Real Job/invoice labor → mechanic work credit → payroll history/payment mapping
  using existing payroll engine, Owner permissions and immutable paid allocations.
- Read-only evidence resolving J-18 and affected invoice picture identities.
- Original package/signing fingerprint, minimum supported Android, version upgrade
  continuity, artifact hash and actual downloadable APK verified before release.

Local Python UI audit and certificate/candidate-gate tests passed (49 tests).
Local Flutter setup was blocked by automatic approval review after an unexpected
instance metadata request; do not bypass it. GitHub CI is the verification path.
