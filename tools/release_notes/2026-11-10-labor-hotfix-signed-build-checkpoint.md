# Briskers labor hotfix signed-build checkpoint — November 10, 2026

Requested by the Owner for the existing Briskers Android app.

Verified source before checkpoint: 3f441a60173a3012f75a6bddbb224a33c87adc71
PR: #447
Target source: same release branch with this documentation-only checkpoint.
Expected package: com.briskers.briskers_app
Expected permanent signing certificate SHA-256:
82075a34ef748541a270af4172dd3ddc37f3e464d9ac9f20eeef7f40a029ff08

Included source corrections:
- Invoice and Job Details mirror the same job-level Main Mechanic selection.
- Owner-only historical Already Paid -> Done per-mechanic settlement, without creating a payroll payment.
- Job Tasks Start orange, Finish blue, Done green; no redundant trailing arrow.
- Completed but unpaid labor-hours correction on existing mechanic allocation (J-50).

Gate verification for 3f441a6:
- Briskers Diagnostics: success (42866002059).
- Android debug verification: success (42866001492).
- iOS compile: success (42866001533).
- Retry storm protection: success (42866001659).
- Offline recurring component: success (42866001977).
- Gloria regression: success (42866001509).

Release conditions: all required checks must pass for THIS new commit too.
Do not report a release until GitHub Actions has actually uploaded the
permanently signed APK, verified the APK certificate and package identity,
and preserved install-over data from the previous Briskers version.

This non-code checkpoint intentionally triggers the configured push workflow.
