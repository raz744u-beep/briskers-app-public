# Independent offline recurrence component

This separate branch now includes the engine, management screen, real expense/
receipt/totals projection, explicit authenticated recovery, recurrence-only sync,
and proposed server endpoints. It is NOT installed or deployed. The active release
branch and live shop data are untouched. Recurrence writes never use financial_create.

Implemented connections: Settings routes to OfflineRecurringScreen; Owner Home
startup/resume generates up to 100 due occurrences using the device's local
calendar (keep the shop device in its shop timezone); manual catch-up can process
additional batches with an explicit shop date. Downloads remain read-only even
in Force Offline. Sync writes require general network permission and an explicit
recurring-sync action. The screen reuses the existing device Owner grant.

The server SQL files are proposed patches, not deployment/migration records.
They must be converted into normal migrations and deployed after validation.
Recovery includes stopped schedules and refuses oversized snapshots rather than
silently truncating (>2,000 rules or >10,000 occurrences). Original receipt files
already on the device are preserved; recovery of remote attachment metadata does
not itself download every remote image. Receipt photos can be attached locally
from the recurring screen; AI recognition still belongs to the separate receipt
AI integration. Conflicts require an explicit Owner choice.

Remaining release verification: apply/test patches against a schema-equivalent
staging database with the real accounting triggers and permissions (the isolated
CI fixture covers the relevant interface, not every production trigger); verify
authenticated RPC transport and final APK update/install on a device. A complete
financial baseline refresh is needed after reconciliation. Deploy offline_recurring_lists.sql along with the recovery and sync patches: the
new list wrapper preserves the legacy filters/order and adds immutable occurrence
keys. Pending list rows overlay by occurrence rather than temporary ID. Full
period reconciliation adjusts the journal to the local-versus-server difference
so a posted occurrence is not counted twice before its ID is acknowledged.

## Files and ownership

- `lib/services/offline_recurring_repository.dart`: isolated SQLite engine.
- `test/offline_recurring_repository_test.dart`: real SQLite restart/rollback tests.
- `.github/workflows/offline-recurring-component.yml`: analyzer, SQLite tests and isolated PostgreSQL tests.
- `recurring_financial_projection.dart`, recovery/sync services and RPC transport: real application connections.
- `offline_recurring_screen.dart`: Owner management, recovery, correction, conflict choice and local receipt capture.
- `tools/patches/offline_recurring_{recovery,sync,lists}.sql`: proposed server patch set.

The constructor takes the existing `BriskersLocalDatabase`, business/user scope,
live authorization callbacks, and a required transactional projection adapter.
The new `offline_recurring_v1` table is created additively. No generated Drift
model changes are required. The branch now includes explicit UI and receipt-service
hooks; review those small shared-file diffs when integrating with the release branch.
All public calls check identity/permissions before and after their transaction.
Callbacks must validate membership and permissions for this business, not just
return whether any user is signed in. Generated data is isolated by user; a second
authorized user/device needs its own authenticated snapshot.

## Data contract

Use server UUIDs for existing rules and fresh UUIDs for local rules. Keep all
existing server transaction IDs. `amount_minor` is a positive integer number of
currency minor units; convert decimal strings exactly in the transport adapter,
not with floating-point truncation. Scope is `business_id`. Direction is expense
or income. Required rule fields: id, business_id, direction, account_id,
category_id, amount_minor, frequency, interval_count, next_date, is_repeating.
Optional fields include vendor_id, counterparty/account/category display names,
remarks, end_date and paused_reason. Server records require integer row_version.

Occurrences also require recurring_rule_id, recurring_occurrence_date, and date.
The occurrence date is immutable even if an expense's accounting date changes.
Local identity is the scoped `(rule ID, occurrence date)` pair. Metadata prefixed
with `_` is local-only and must not be sent as server columns. `_revision` is an
optimistic token for acknowledgement; `_state` is synced/pending/conflict.

Month/year stepping deliberately matches the existing server's PostgreSQL
clamping behavior (Jan 31 -> Feb 28 -> Mar 28), not an invented anchored-month
policy. Use the shop's calendar date for generation. The latest occurrence amount
is inherited, matching the existing server processor; unrelated receipts/invoice
numbers are never copied. This policy means a schedule's default amount does not
override an already-corrected latest occurrence.

## Integration contracts (now implemented; verify at release)

1. Provide the projection callback. It runs in the SAME SQLite transaction and
   must use the supplied database. Upsert the expense list/detail and totals
   journal once, by occurrence key. On acknowledgement remap local/server IDs,
   receipt upload references and totals identities without counting twice.
   Preserve original receipt files, metadata, unrelated expenses and pending
   edits. Do not use I/O or networking in this callback. Throwing rolls back the
   whole occurrence and schedule update. Ensure ordinary limited cache refreshes
   preserve locally generated recurrence entries as well as downloaded ones.
2. Add an explicitly invoked download that bypasses only the general-sync network
   gate for authenticated read-only recovery. Capture the initiating user and
   reject results if identity changes. Fetch ALL schedule pages (including stopped
   rules), supporting options, and posted occurrences with versions and keys
   before importing. Fetching only the active list loses remote stops. Never
   infer deletion from an absent record or a partial response. The existing
   single-occurrence download can remain a shortcut; this engine does not assume
   that its endpoint has been deployed.
3. Read management screens from `rules()` even without an old preferences cache.
   Create/edit/stop through `saveRule()`. UI must preserve stopped records, show
   conflicts, and not imply cached records are freshly server-confirmed.
4. Call `generateThrough(shopDate)` on authorized app startup/resume and after
   schedule changes. Repeat bounded catch-up batches as needed. Each batch
   commits occurrences, cursor advancement and projections together. Do not
   promise generation while an offline app is closed. Validate cached account,
   category and payee availability in the adapter; pause invalid rules.
5. Implement recurrence-specific authenticated server CAS/idempotent operations.
   Persist occurrences BEFORE acknowledging a cursor advance. Serialize with the
   server scheduler using the same rule row lock. Use the existing server unique
   index `(business_id, recurring_rule_id, recurring_occurrence_date)`, returning
   the existing canonical transaction on retry. Include required accounting
   allocations. Do not call the manual-expense creation endpoint for occurrences.
   For rule edits/stops, compare the downloaded row_version; do not silently
   overwrite a server change. An offline stop cannot undo expenses a disconnected
   server already posted: surface those for Owner resolution.
6. Pass the exact sent `_revision` plus returned canonical row to `acknowledge()`.
   A newer local edit rejects an old response. Different financial contents are
   kept as a conflict, not silently accepted. Download alone never acknowledges
   pending operations. An explicit conflict-resolution flow must reconcile the
   chosen content on the server, then acknowledge that content with its current
   local revision. Do not clear pending rows merely because an upload returned
   HTTP 200. Keep general sync disabled until these adapters are verified.

## Acceptance before release

- Download existing schedules and occurrences onto an initially empty device.
- Restart offline; records and attachments remain available.
- Generate an already-downloaded date: no extra expense or totals change.
- Generate next date; restart and repeat: one expense only.
- Correct latest amount: following occurrence inherits it; old receipt is absent.
- Interrupt projection / revoke authorization: cursor and expense both roll back.
- Two devices/server create same occurrence; reconnect twice: one canonical entry,
  correctly remapped local receipts, no double totals.
- Concurrent local edit during upload is retained; server conflict is visible.
- Stop offline, inclusive end dates, leap years, old schedules and inactive
  references behave consistently with the server.
- Verify regular Expenses, receipt attachment, totals and update-install data
  preservation on the final integrated APK. Component tests do not establish this.

No customer records, account credentials or live financial snapshots are included.
