# Briskers Payment Edit v2 — Active Schema Release Preflight

**Date:** October 17–18, 2026 UTC. **Status:** Review only; migration **not applied** to active Briskers Dev.

## Verified by read-only SQL against the active Briskers Dev schema

- All 5 expected legacy RPCs exist: `briskers_add_pending_invoice_payment_once`, `briskers_update_pending_invoice_payment`, `briskers_finalize_pending_invoice_payment`, `briskers_document_detail_v3`, `briskers_invoice_receipts_v1`.
- All 8 required `briskers.invoice_pending_payments` columns and 6 operation-key columns exist.
- Payment tables have RLS enabled. `briskers.require_permission` is SECURITY DEFINER and checks `auth.uid()`.
- Existing `sync_invoice_status_from_pending` trigger is enabled; editing payment rows also bumps `sales_documents.row_version`.
- No active `briskers_*_v2` or `briskers_document_detail_v4` payment RPCs yet. Old clients retain legacy RPC compatibility.

## Source corrections after the two earlier isolated synthetic tests

1. The actual payment screen now exposes an Edit menu for pending-sync receipts. An earlier restore had accidentally reinstated the old UI, despite supporting services being present. A source-wiring regression test prevents recurrence.
2. `InvoiceFinalizationGuard` now blocks when EITHER `invoice_payment_received` OR `invoice_pending_payment_edit` remains queued, regardless of outbox state. It does not delete or decode these queues.
3. For legacy v1 receipts missing `payment_date`, finalization uses `entered_at::date` rather than the later finalization date. For new v2 receipts, device-local `payment_date` is captured immediately; `entered_at` and `entered_by` stay immutable.
4. `briskers_invoice_receipts_v1` pending date is `COALESCE(payment_date, entered_at::date)`; posted date remains the authoritative `financial_transactions.transaction_date`.
5. Client-reported pre-sync edits travel with the original operation UUID as JSON history (max 100 events / 32 KiB). This is unverified client provenance, not a server-trusted audit; the server edit audit logs authenticated actor and previous/new values.
6. Owner Delete/Remove is blocked in the payment menu for Force Offline, queued server corrections and locally pending receipts; server-only delete should not be used to remove a local outbox receipt.

## Latest source tests

- Flutter Android Diagnostics: workflow 39087255161 **SUCCESS** on SHA `f7e940cd7a92f5cfeb7f4e8c028e692487cbd45d`.
- iOS compile: workflow 39087255141 awaiting final conclusion at preflight.
- Two private synthetic Supabase branches were created using owner-approved <$1 budget and both deleted; tests exercised idempotency, historical posting dates, stale edits and RLS grants on minimal fixture schemas. **Not** a full copy of active schema.

## Approval and rollout boundaries

1. No live migration, payment DML, sync, finalization, owner-phone mode change, merge or signed APK yet.
2. Source and SQL changes remain review-only PR #214 stacked on UI PR #213 and stabilization PR #209.
3. Before active schema deployment, obtain explicit owner approval **separate** from synthetic test authorization. Back up/record existing function definitions and deploy atomically with versioned migration; verify RLS/grants and required RPC functions post-deploy.
4. No production data should be used for synthetic writes. Preserve Janet Williams #6348 $175.60 pending local receipt and Sara Mirza #6345 pending server receipts exactly; they must be reconciled read-only before phone sync.
5. Only after backend migration is verified should a permanently signed APK be built for testing one step at a time; do not uninstall or clear local data.

## Live function drift fingerprints (read-only; recheck before applying)

MD5 hashes of PostgreSQL `pg_get_functiondef` from the active database on October 17–18 UTC. These are **drift detectors**, not integrity/authenticity guarantees. If any differs at deployment time, stop and review the changed function definitions before proceeding.

| Function | Definition MD5 |
|---|---|
| `briskers_add_pending_invoice_payment_once` | `8974d0dea016b4e517662617aaaf6404` |
| `briskers_document_detail_v3` | `ba0c737c22530b0a9060d81a857be191` |
| `briskers_finalize_pending_invoice_payment` | `816e2e0a1d03cb3f67c5dba719089b10` |
| `briskers_invoice_receipts_v1` | `633a79598d697a407e61ad4f5f86c711` |
| `briskers_update_pending_invoice_payment` | `dbbf7190d3e0ae56a508b62af676c36f` |

No routine was altered by retrieving these fingerprints.
