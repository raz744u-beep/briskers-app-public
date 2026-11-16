# Bugs 35 — Owner-approved visual specifications

The two original attachments supplied by the Owner on November 11, 2026 are authoritative. Gallery, Android system, and image-editor overlays in Picture 1 are not app controls.

- `approved-shared-list.jpg`: one white-card layout for Jobs, Service Tasks, and Invoices. Preserve the existing status meanings and navigation. Invoices substitute total, balance, and payment information for task progress.
- `approved-invoice-mechanics.png`: Warranty Job and Main Mechanic share a row. The full-width label below sums saved labor-line allocations by mechanic nickname and shows a read-only total. Narrow phones may wrap the summary without clipping. Existing per-line pencil editing stays intact.

Original SHA-256:

```
822984adbb8b0d958a36a249038e5f0f4ed7ff102900e82c547d43cf767ebdc1  approved-shared-list.jpg
9fc72f4868a743300c7a6f42aa97341f784e16a18ba9bd8d270ef6d339713cce  approved-invoice-mechanics.png
```

Implementation uses `JobListApprovedCard` and `ApprovedListStatusBadge` across all three lists. Invoice lifecycle and financial coverage remain separate from labor completion. Estimates retain their existing layout.

Historical completion is a read-only projection of exact allocation/employee/business-matched historical settlement markers or full minute coverage backed by a payroll payment. Partial, orphaned, mismatched and uncertain records are not completed. No production records are edited and no fabricated payroll payment is posted. J-44 and J-45 are subject to the same evidence checks as every other job; their phone-local evidence cannot be certified from a synthetic test.

Verification fixtures: `test/bugs35_shared_design_test.dart`, `test/bugs35_verified_paid_labor_test.dart`, existing assignment/split, paid-history, navigation, and frozen Jobs tests. Rendered fixture PNGs are uploaded by Diagnostics as exact-source payroll widget QA. Signed upgrade verification now includes the previous b4627 APK and checks retained synthetic offline records across `adb install -r`.
