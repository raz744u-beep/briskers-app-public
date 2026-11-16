# Payroll methods — issue #297

Status: specification complete; payment UI/sync not implemented on this branch.
This correction branch has employee settings and manual financial transactions,
but no payroll payment entity, task payroll workflow, or payroll proof upload
contract. Do not treat a local settings preference as a completed payroll system.

## Data and entry behavior

- Shop-owned methods have stable IDs, name, enabled flag, sort order and version.
  Seed Cash, Check, Zelle and ACH. Rename/disable never deletes history.
- Employee default references a method ID, not a bank account or category.
  Preserve actual employee IDs/names, including Chris Rideaux, Kamerron and Adam.
  Nicknames are display-only; do not merge identities by matching labels.
- Each payment records immutable payment ID/operation UUID, business/employee,
  method ID and label snapshot, date, amount in cents, source account, optional
  reference, payroll week, task/job allocations, proof attachment ID and version.
- New entry selects the employee default; Owner can override for that payment.
  Missing historical method displays “Not recorded”; never infer from account.
- Advance, partial/split payments and Owner overrides are distinct operations.
  Actual amount is posted once through the same accounting transaction; Payroll
  remains the category. Source account remains a separate field.

## Check proof and offline contract

Check method requires a photo saved durably in private app storage before the
payment draft can be submitted. Copy picker bytes atomically, verify readable,
record length and SHA-256, retain across restart, and mark upload pending.
Never depend on a temporary picker URI or public/shared gallery location.
Offline submission saves the proof record and payment operation in one local
transaction. Upload must converge to a deterministic shop/payment/proof key,
private bucket and authenticated access; cross-shop reads must be denied.
Post only after server validates proof ownership and checksum. Lost responses
reuse the same operation UUID and attachment key. Never create a second expense
on retry, attachment replacement, reconnect, or cross-device refresh.

## Screens and permissions

Owner Settings → Payroll → Payment Methods: add, rename, disable, reorder;
show historical usage; prevent deleting used methods. Employee editor: default
method selector. Payroll confirmation: method override, separate source account,
actual amount, date, optional reference and required Check photo preview/status.
Unauthorized staff cannot post payments or read unrelated payroll proofs/totals.
A required unavailable server capability must fail closed with a saved draft.

## Required implementation and acceptance sequence

1. Review payroll operation/attachment backend and permission contracts separately.
   No deployment is included in this correction branch.
2. Implement durable local records/outbox and reconciliation, then the screens.
3. Test every default/override, historical label retention, disabled methods,
   Check without photo, restart with pending proof, upload interruption, lost
   posting response, split payment, duplicate replay and cross-device sync.
4. Verify exactly one financial transaction per operation and unchanged imported
   payroll amounts/dates/employee identities. Exercise tenant/role isolation.

Do not enable payroll posting based solely on client-side validation.
