# Payroll methods — issue #297

Status: Owner-only local draft preparation and local method configuration are
implemented; server payroll registration/posting/sync remain unavailable.
Settings → Employees → Payroll Drafts → Payment methods & employee defaults
supports add, rename, disable, reorder, durable UUID identities, and per-employee
defaults with a per-draft override. Local configuration is isolated by shop and
Owner. These UUIDs are not proof of server registration and are never submitted.
Older provisional draft methods require an explicit new choice; no automatic
mapping by name. Renames leave saved draft label snapshots unchanged. Imported
payments are untouched; unknown historical methods must not be inferred.

An isolated durable outbox engine now freezes an operation and proof manifest
in one SQLite transaction. It rejects changed payloads and draft edits/discard
after enqueue; restart/lost-response retries reuse the stored server method
mapping and operation. It requires an explicitly reviewed gateway capability,
and only an authoritative matching receipt marks the queue posted. The app has
no active gateway or enqueue/post UI: this is tested integration groundwork.
No actual payment, upload or payroll expense is enabled. Local
source account IDs are preserved when editing, but account selection/validation
and verified Payroll category resolution still require the backend contract.
Check photos remain app-private device copies, not remotely verified attachments.
The screen says NOT PAID. This is not completion of #297.

Owner route identity and shop are captured at entry. Auth changes revoke that
route permanently, clear sensitive state and dismiss confirmation dialogs; late
loads/photo results cannot repopulate it. Every write uses the captured actor,
with context rechecks after awaits. These guards supplement server authorization.

Check proof is decoded and checksum-verified on reopening/saving. Header-only or
truncated images cannot qualify. Changing employee, operation, method, amount,
calendar date, payroll week, account or reference invalidates reuse. The Owner
must choose/reconfirm the photo for the changed terms. JPEG/PNG/WebP decoding is
supported locally within size/pixel limits; HEIC fails closed pending a verified
cross-platform conversion path. No unsupported bytes are marked verified.

### Proof retention and cleanup policy

No automatic deletion is enabled. A future cleanup transaction must collect all
references from drafts, frozen operations, proof queues and acknowledged server
records, including pending/submitted records. Preserve any referenced file and
all unknown states. Only unreferenced versions of explicitly discarded unpaid
drafts may be proposed for deletion after a grace period, with a per-operation
filesystem lock shared with staging and a final reference check. Server proofs
remain immutable; retention/deletion requires a separate reviewed policy. Draft
discard currently removes the draft row and deliberately retains private bytes.

## Remaining backend gate

A read-only function inventory on October 23 found the customer payment RPC but
no payroll/proof RPC in the app schemas. Before implementing a posting adapter,
review a private backend contract for method registration/reconciliation, stable
operation UUIDs, employee membership, eligible source accounts, Payroll category,
Owner/authorized-office permissions, proof ownership/checksum/private storage,
and atomic idempotent ledger posting. Validate against an isolated current schema
with synthetic fixtures: concurrency, lost responses, restart, cross-device
replay, permission denial and exactly one expense per operation. No guessed RPC
or raw client ledger insert is an acceptable fallback. Local UUIDs need explicit
server acceptance or a durable ID mapping before any submission can be enabled.
Backend deployment and any historical repair require separate approval.

## Correction batch acceptance gates

- #292 compact Jobs filter: client correction; Owner visual acceptance pending.
- #293 Customers category: 24 local synthetic PostgreSQL assertions pass. Patch
  and guarded repair remain review-only; current-schema trigger/concurrency and
  fee-report integration validation, deployment and real repair are not done.
- #294 canonical mechanic display: client correction; Owner acceptance pending.
- #295 consolidated local Service History: client correction; offline/reconnect
  and cross-device Owner acceptance pending.
- #296 compact saved-data indication and Estimate tabs: client correction;
  Owner visual/navigation acceptance pending.
- #297 local draft/configuration only; backend, financial outbox/posting, secure
  upload, authorized-office/mechanic views and Owner acceptance remain open.

Passing code/CI or producing an APK does not close these six issues. Signed
regular candidate preparation does not authorize installation or deployment.

## Phase 2 (#305) reconciliation — deferred

After all six corrections and Owner acceptance: invoice-first optional Main
Mechanic; durable labor-line Tasks; separate editable billed hours and mechanic
estimates; read-only summed Job estimates; preserved completed tasks on recheck;
Work Completed history with nickname/actual hours and universal offline search;
no standalone Work Performed log. Profitability stays Owner-only and excludes
company-only processing fees/interest. Define behavior for *uncustomized* Task
estimates when billed hours change before implementation. No Tasks code is part
of this continuation and neither existing device app is modified.

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

The prepared v1 transport has a source-level closed deployment gate. It cannot
be enabled by a server response or setting and is not attached to a submit
action. Private server/Storage verifier proposals are tested separately and
require backend approval and integration validation before activation.
