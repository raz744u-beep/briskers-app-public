# Bugs 35 overnight release

Continues PR #447 / issue #454 on `fix/bugs33-preserve-offline-financial-history-20261108`, including all implementation through d14567f and the repaired permanent-signing workflow through 447c8d75. Build 4632 is the installation baseline. No new app, package, signing key or production-data migration is introduced.

## Included

- Historical invoice labor through November 8, 2026 displays Done and is excluded from new payroll unless explicitly carried forward. Current work begins November 9. Existing general tasks on historical jobs display Done except future reminders; new reminders remain active.
- Owner assignment/hour corrections on historical Done/Paid/Closed work are stored separately from immutable payroll credits and payments. A second mechanic can be added without creating wages. Job and invoice hour summaries show corrected records.
- Invoice list/detail presentation uses Open, Paid and Closed, calculated from saved coverage and confirmed closure. Pending local receipts may cover the customer balance; they are not represented as posted income. Voided records retain their administrative Void identity, outside the three active filters.
- Finalize-then-close preserves the first request and payment identities. A durable closure-only followup handles changed closure intent and survives lost responses. Changed financial amounts still require reconciliation rather than silently replaying payments.
- Complete saved recurring expenses open in the existing local editor using their original IDs, even without a generic manual-transaction detail response. Amount/account/category/payee fields and photos remain local. Missing edit targets cannot open as blank, saveable forms.
- Existing recurring rules catch up on app opening/resume with occurrence uniqueness; edited amounts carry forward. Refreshes preserve historical transactions and local photos. No Supabase historical records are deleted.
- Existing shared compact Jobs/Tasks/Invoices cards retained; invoice chevron removed, repair line compact, invoice footer combines total/mechanic hours/date, Open blue, Paid green, Closed gray. Missing VIN reads “Not entered.”
- Existing permanent signing and release prerequisites retained. Upgrade gate now uses signed b4632, after the original b2568 payroll baseline.

## Verification and remaining limits

Focused tests cover historical paid-ledger immutability, restart, future/new general reminders, Cintas cached fields/amount/photo persistence, duplicate occurrence protection, and finalization retry identity. Existing financial-history, payroll LAN/idempotency, local-data and install-over tests remain required. The release is not accepted until CI and signed artifact verification finish.

Remaining: historical recordkeeping corrections are local to the editing device and do not yet propagate as corrected display metadata to other phones over LAN. Original payroll payment/credit synchronization remains unchanged. Existing general tasks without any dated job/document evidence are not guessed to be historical. Recurring catch-up runs when the app opens/resumes; it does not wake a terminated Android app. A rule/expense that has never been stored on a phone still needs its existing authorized recovery/download. Finalization with genuinely changed payment data remains held for reconciliation. Physical-phone acceptance of Cintas and the exact card typography remains necessary; synthetic tests cannot inspect the Owner's private phone database.
