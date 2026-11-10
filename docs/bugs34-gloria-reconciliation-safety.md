# Bugs 34 — Gloria invoice reconciliation safety gate

This is a READ-ONLY investigation document, not a production migration or fix.

## Verified

- Job J-40 (`c6a23164-c09a-490d-8b00-c3e84e7282fb`) server status `open`, row version 1.
- Invoice #6359 (`4bc125a0-7954-4036-82f2-4650847463f3`) server status `issued`, no `closed_at`, row version 6, total $7,882.11.
- Server pending payment $3,000 (`9d31e9fb-ae9a-465a-9d12-60a3a0cf1547`); no linked allocations found in read-only queries. Phone UI displays two entered payments ($3,000 + $4,882.11), $0 finalized, $7,882.11 pending sync.
- `_finalizeEnteredPayments` refuses Force Offline or queued receipt operations. `OfflineInvoicePaymentLedger` records receipts but explicitly does not finalize.
- `public.briskers_finalize_pending_invoice_payment` iterates server pending rows, calls `briskers_record_payment` with a fresh `gen_random_uuid()` and deletes pending rows. `public.briskers_close_invoice` invokes finalization when server pending rows exist. Neither function can be safely assumed to reconcile the phone's queued receipt identities.

## Fail-closed rules

1. Never call current finalization or close RPC against Gloria before matching original phone operation UUIDs to server pending/payment/transaction IDs.
2. Never remove Force Offline, initiate broad sync, or modify phone outbox while investigating.
3. Capture a read-only local snapshot with outbox operation IDs, state, attempt count, payload, local invoice and job status/version, and the two payment records. Treat this as private financial data.
4. Resolve whether the $3,000 server pending payment corresponds to the phone's original $3,000 receipt; matching amount alone is insufficient.
5. Any future replay must preserve stable operation identity and be exactly-once, including retries and lost responses; no blind `gen_random_uuid()` for an already recorded payment.
6. Test synthetic scenarios: both payments local, one acknowledged server-side, finalization crash after server commit, repeated replay, stale server status, restart, zero balance without posted allocation, and existing pending payment with no matching UUID.
7. Distinguish `received locally`, `posted/reconciled`, `invoice closed`, and `job completed`. Never display verified closure without ledger evidence.
8. Obtain explicit Owner approval for exact production financial changes only after reporting the reconciliation plan and affected IDs.

## Not yet verified

Phone SQLite and outbox operation IDs; server matching identity for second receipt; safe production reconciliation; actual closed status after restart/sync. PR #447 must remain untouched.
