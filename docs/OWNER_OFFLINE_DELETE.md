# Owner Delete v3 — regular offline app

The regular Job menu's **Delete Job** action uses the saved Owner account, Android device unlock and one linked-record confirmation. It performs no network request. The Owner decides which transaction to remove, including a paid local transaction. The older server retirement and synthetic test adapters retain their separate restrictions.

This integration includes the b2545 release source (`6b17b22803eda02352dc1a7d9812229f03fa3fb4`), preserving its recovery, payment and startup fixes.

## Local commit

Job rows, linked invoices/estimates, visits, assignments, findings, inspection metadata, queued operations, ordinary document details, matching financial cache entries, deletion markers and number reservations share one SQLite transaction. Preview changes, authorization expiry or any database failure abort the complete deletion. Customers, vehicles, unrelated transactions and existing recovery evidence remain intact. Shared cross-Job records require their relationship to be resolved first.

The regular startup enables SQLite document details. Old preference snapshots are imported lazily, without changing original recovery evidence. Permanent local tombstones prevent stale details and index rows from returning after restart. Existing list retirement notifications also refresh the Jobs and Invoices views.

## Numbering

New offline invoices receive the next local invoice number. New Jobs receive the next local J-number. Creating an invoice from an existing Job retains that Job. SQLite serializes allocation and checks existing indexed numbers and active reservations. Deleting the latest allocation rewinds the free suffix; deleting an older allocation leaves it available for manual assignment.

Owners can set the next invoice/Job number in **Settings → Document Numbering**. An invoice's header menu contains **Assign invoice number**; a number already used by another local invoice is rejected and the original assignment remains intact. Existing invoices are never automatically renumbered. Newly device-numbered creation operations remain held locally; server number reconciliation is outside this release.

## Samsung acceptance

1. Install the signed APK as an update to Briskers; do not uninstall or clear app data.
2. Use the saved Owner account and an Android PIN/fingerprint. Keep Force Offline enabled and turn on airplane mode.
3. Check Settings → Document Numbering for the intended next invoice and Job numbers. Confirm existing recovered records and original payments remain visible.
4. Create a customer, vehicle and Job. Create an invoice from the Job, add labor and a part, then record a cash test payment.
5. On the Job, choose Delete Job, unlock the device and confirm the linked records once. Check Jobs, Invoices and payment views. The customer and vehicle remain.
6. Close and reopen Briskers while still offline. Confirm the deleted transaction remains absent.
7. Create the next transaction and verify the latest freed invoice/Job numbers are reused. For an older freed invoice number, use Assign invoice number. Attempt an occupied number and verify it is rejected without changing either invoice.

Automated tests cover the real local creation/payment/deletion services, an existing Job invoice, restart persistence, latest and older number reuse, concurrent allocation, rollback, changed previews, failed authorization, stale-row fences and preservation of unrelated recovered financial history. Physical Samsung installation and OS unlock are acceptance checks on the device.
