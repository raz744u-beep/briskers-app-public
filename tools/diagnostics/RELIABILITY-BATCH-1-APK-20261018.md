# Briskers reliability batch 1: signed Android QA request (Oct 18, 2026)

Source: draft PR #229 (fix/offline-roster-invoice-refresh-20261018) based on signed b2311.
Purpose: validate per-user/shop minimal employee roster offline (no pay/SSN/contact data), cross-screen Job/Appointment assignment, settings read-only cache, and instant server-confirmed invoice-close list changes.

Already tested paths in baseline: recurring management offline read-only fallback; Expenses local detail and first-page performance.
No financial RPC or Owner Delete changes; no production DML by build.

Installation: signed existing package com.briskers.briskers_app, permanent certificate SHA256 82075a34ef748541a270af4172dd3ddc37f3e464d9ac9f20eeef7f40a029ff08; versionCode strictly higher than b2311; install over existing app, never uninstall or clear app data.

Phone acceptance, one at a time:
1. In Auto Settings → Employees verify updated active+inactive list; note correct names/positions, do not edit live payroll fields.
2. Switch Force Offline; Settings → Employees shows saved read-only roster and no Bad state/no false zero; Job → Assign Employee and Appointment planned mechanic show current active roster.
3. Return Auto and verify a safe refresh; no sync outbox duplication and role permissions unchanged.
4. Invoice list immediate close transition test ONLY on an authorized synthetic/new no-money fixture. Do not re-finalize Barbara #6349 or create a payment for an existing invoice.
5. Recurring Transactions and Expenses & Income offline viewing smoke tests; no mutations.

Track CI, APK signer, phone and iOS status independently. No live deletion, payment finalization, or modifications authorized by artifact creation.
