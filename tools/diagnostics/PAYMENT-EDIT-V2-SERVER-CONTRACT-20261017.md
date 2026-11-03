# Payment date v2 backend contract — review required before deployment

**Status:** Proposed only. Neither the active Briskers Dev Supabase database nor any production receipt has been modified by this draft.

## Existing live contract (read-only verification 2026-10-17)
- `public.briskers_add_pending_invoice_payment_once(business_id, invoice_id, amount, method_id, operation_id)` deduplicates by operation UUID, with an immutable amount/method identity. No business payment date parameter.
- `public.briskers_update_pending_invoice_payment(business_id,payment_id,amount,method_id)` edits amount/method with authorization and available-balance checks, not date.
- `public.briskers_finalize_pending_invoice_payment` calls `briskers_record_payment(...,current_date,...)`; this **loses historical payment dates** even if a phone changed its display.
- `invoice_pending_payments.entered_at` is a timestamp of capture, not a user-editable shop business date. `financial_transactions.transaction_date` is the posted business date.
- `briskers_document_detail` returns payment `entered_at`, but not a separate payment date.

## Required reviewed database changes
1. Add nullable `payment_date DATE` to `briskers.invoice_pending_payments` and `briskers.invoice_payment_operation_keys`, **without backfilling or rewriting original entered_at**.
2. Introduce RPC `public.briskers_add_pending_invoice_payment_once_v2(business_id,invoice_id,amount,method_id,operation_id,payment_date)`. Require payments.create, validate amount, date and active method; lock same operation key and reject reuse with *different date/amount/method*, saving the effective date atomically with one receipt. A lost response must retry idempotently and return same payment identity.
3. Introduce guarded, version-locked `briskers_update_pending_invoice_payment_v2` for server-pending (unfinalized) receipt ID with new amount, payment date and method. Lock existing payment and invoice, enforce overpayment checks inclusive of all other receipts, permission checks, audit old/new values and actor, and update any associated operation-key record consistently. Fail closed on posted/finalized payments and concurrent changes.
4. Date-aware `briskers_finalize_pending_invoice_payment` must post `coalesce(payment_date,current_date)` as the *financial transaction date* while preserving actual processor event time and approval identity. Old app versions must also honor the correct date on already-saved pending payments.
5. Return `payment_date` in document-detail payment entries as a separate JSON field. Receipts with NULL date continue to show original entered_at. Use payment_date in Expenses & Income projections, PDFs, and invoice screen; do not represent unfinalized receipt as posted income.
6. Audit table includes operation/payment ID, invoice/business/user, previous/new amount/method/date, server timestamp and operation origin. Ledger records are never silently overwritten after finalization.
7. All SQL must use security-definer search_path empty, parameterized IDs, existing RLS/permission checks and explicit grants, with schema-specific qualification.

## Acceptance gates
- Synthetic $0.01–$1.00 isolated test branch only if separately authorized; never mutate actual Briskers customer invoices as a migration test.
- Save offline, restart, edit same UUID several times, reconnect after server migration, exactly one pending payment and correct date; then post in synthetic environment with matching `transaction_date`.
- Force a lost network response after receipt acceptance, retry UUID unchanged and no second server receipt.
- Simulate another device editing/finalizing first: local attempt must fail closed with conflict, never duplicate or refund card payment.
- Verify new payment #6348 logic using *read-only* inspection until owner explicitly authorizes production reconciliation.
- Android Diagnostics, iOS compilation, signed APK and owner phone acceptance tracked separately.

**Do not merge PR #214, ship its editor, run payment sync or apply this migration to the live shop until all gates pass.**
