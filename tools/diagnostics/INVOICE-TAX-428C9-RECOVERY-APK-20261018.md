# Recovery build request — 2026-10-18

Source draft PR: #227 (fix/generated-total-tax-428c9-20261018)
Backend migration: invoice_tax_generated_total_fix_20261018, deployed successfully on Briskers Dev with Owner approval; rollback-only synthetic test passed.
Purpose: signed install-over Android APK to recover one known previously rejected (428C9) *inflight* local tax operation, **without retrying automatically or deleting existing accounting**.

Phone acceptance:
1. Install over existing Briskers; do not uninstall or clear app data.
2. Stay Force Offline. Confirm invoice #6349 outbox tax #111 inflight and pending-payment edit #112 pending.
3. Only after controlled explicit instruction: switch to Auto and use the **Owner-only "Verify rejected tax update #111"** button to attest server patch + original invoice version/lines. The action merely requeues #111; it does not send invoice/payment writes.
4. Explicit next coordinated sync should send tax #111 before payment correction #112, retaining original pending-payment UUID. Never delete/re-enter/finalize the receipt.
5. Verify corrected invoice $175.60 / one pending payment $175.60, no duplication, account remains unfinalized, and no remaining financial outbox.
No production SQL DML, payment finalization or phone synchronization authorized by APK creation alone.

Release requirements: permanent signer, exact package com.briskers.briskers_app, versionCode newer than installed b2310, analyzer/tests, APK artifact and certificate verification.
