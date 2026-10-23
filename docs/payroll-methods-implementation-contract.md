# Payroll methods — issue #297

Status: Owner/authorized-office drafts, authoritative catalog/default/history cache,
confirmation, frozen outbox replay, earned-labor allocation and receipt UI are
implemented with a source
approval gate that remains **off**. No live payroll submission is enabled.

Local methods have stable registration keys. Confirmed catalogs use distinct
server UUIDs, never provisional IDs or label matching. The confirmed cache and
pending configuration queue survive restart and are scoped to shop and actor.
Add/rename/disable/reorder and employee defaults use immutable mutation IDs and
optimistic versions. Conflicts retain pending edits while refreshing history.
A per-payment override, separate source account and independent payroll week
are supported. Confirmed earned labor can receive full/partial allocations; Job
labels must be cached before selection. Unallocated remainders remain advances
or extra amounts. Task creation remains deferred to #305. Unknown historical methods display Not recorded, without account
or current-label inference. Imported amounts/dates remain unchanged.

With a separately approved backend and code activation, a saved payment requires
explicit confirmation before its payload/proof are frozen atomically. Lost
responses retry the same operation; queued payments remain NOT PAID until a
matching authoritative receipt. Pending/void receipts never appear as posted.
The production build cannot activate posting from a server flag or user setting.
Private synthetic contracts and actual local service tests exercise this future
path; they are not evidence of hosted deployment or live financial acceptance.

Owner route identity and shop are captured at entry. Auth changes revoke that
route permanently, clear sensitive state and dismiss confirmation dialogs; late
loads/photo results cannot repopulate it. Every write uses the captured actor,
with context rechecks after awaits. These guards supplement server authorization.

Check proof is decoded and checksum-verified on reopening/saving. Header-only or
truncated images cannot qualify. Changing employee, operation, method, amount,
calendar date, payroll week, account or reference invalidates reuse. The Owner
must choose/reconfirm the photo for the changed terms. JPEG/PNG/WebP decoding is
supported within size/pixel limits; WebP is normalized to PNG. Native image
picking requests JPEG conversion without metadata and bounded dimensions. Direct
HEIC bytes fail closed. Native camera/library HEIC acceptance still needs device
review; no unsupported bytes are marked verified.

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

Private review-only SQL, proof verifier and synthetic tests have been prepared
outside this public repository. They cover registration, permission checks,
source/category separation, immutable proof, transaction replay, current ledger
triggers, catalog defaults and historical labels. Actual localhost Auth,
PostgREST, Storage and Edge tests passed with synthetic users/objects. No private
schema is published here. Reserved server registration keys seed Cash, Check,
Zelle and ACH once per shop, preserving later renames/disabling across devices. The expanded SQL fixture includes all foreign keys in the dependency closure.
It applies 36 of 71 inventoried triggers; 35 omitted triggers still require full
migration and ACL rehearsal. Actual service tests use the earlier selected
fixture. Neither fixture establishes hosted deployment readiness.

Deployment still requires explicit approval, full migration/ACL review and a
separate code activation. Historical customer-category repair also requires
separate approval. The current artifact cannot post payroll. Permission-aware office/mechanic entry points are implemented. Office management
requires a fresh server grant; personal records are cached by actor/shop and
exclude source accounts, proof URLs and company totals. Revocation/auth switching
fails closed. Native camera/library HEIC acceptance, full migration/ACL validation,
backend deployment/activation and Owner acceptance remain explicit gates.
Reference-aware cleanup remains deliberately disabled under the policy above.

## Correction batch acceptance gates

- #292 compact Jobs filter: client correction; Owner visual acceptance pending.
- #293 Customers category: 24 local synthetic PostgreSQL assertions pass. Patch
  and guarded repair remain review-only. Private selected-current-schema tests
  also preserve protected fields under existing ledger triggers. Deployment,
  real repair and Owner report acceptance are not done.
- #294 canonical mechanic display: client correction; Owner acceptance pending.
- #295 consolidated local Service History: client correction; offline/reconnect
  and cross-device Owner acceptance pending.
- #296 compact saved-data indication and Estimate tabs: client correction;
  Owner visual/navigation acceptance pending.
- #297 gated client, allocation editor, office/mechanic UI and private synthetic
  backend prepared. Full deployment validation, activation and Owner acceptance
  remain open; live payroll is not enabled.

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
