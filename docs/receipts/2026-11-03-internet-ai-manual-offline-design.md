# BRISKERS — Internet AI receipt scanning, manual offline

**Decision:** November 3, 2026. Replaces the mandatory on-device receipt OCR objective in issue #411. Design only: no production build, server, or financial data change.

## Purpose

Return to the accurate online-AI receipt experience while ensuring **neither receipt recognition nor expense saving requires Supabase**. If the internet is unavailable, use the existing Quick Transaction or Full Manual paths with optional receipt photo attachment. No mandatory on-device OCR.

### Three choices

| Receipt option | Internet available | No internet | Supabase down | Force Offline sync mode, internet available |
| --- | --- | --- | --- | --- |
| AI Scan Receipt | Available after consent; independent HTTPS gateway | Unavailable; continue manually with same photo/draft | Available | Available, no Supabase synchronization |
| Quick Transaction | Available | Available from locally cached templates | Available | Available |
| Full Manual | Available | Available | Available | Available |

"Offline" for AI means **no internet**. The Briskers Force Offline setting disables *Supabase synchronization*, not independently authorized external AI traffic. Do not confuse these settings. The user may decline any AI upload and still save locally. If saved Quick Transaction templates or account/category options have never been cached, show this clearly and permit manual drafting without pretending data exists.

## User interface

Keep the existing Expenses/Add Expense design. Three primary actions: AI Scan Receipt, Quick Transaction, Full Manual. Attach Photo is available on quick and manual paths both online and offline. Avoid redesign of transaction fields, posted records, categories, tax, warranty or surcharge.

AI Scan: Camera or Gallery -> attach original photo exactly once -> ask permission to send to independent AI -> recognize -> review and correct -> local save. User can cancel AI review, continue with the SAME draft/photo manually or select Quick Transaction. No stalled spinner on unavailable gateway.

Quick Transaction: cached preset supplies vendor/payee/category/account/description defaults; edit all fields; optionally attach original receipt; local save.

Full Manual: enter vendor/payee, amount, date, category, account, description; optionally attach original receipt; local save.

Only Save Transaction creates a financial transaction. Keep statuses separate: photo attached, AI suggestions available/reviewed, expense saved locally, Supabase sync queued/succeeded/failed.

## AI architecture and security

Phone -> independent HTTPS receipt gateway -> AI provider. No Supabase Edge Functions, no Supabase authentication lookup on every request, no Supabase database requirement for scanning.

Gateway requirements: gateway-issued per-shop/device credential in Android secure storage, scoped Owner/Secretary permission and revocation; per-shop rate limits, request limits, size and MIME checks, timeout; provider API key as a server-side **secret**, never shipped in APK or committed to GitHub; encrypt transport; never log receipt images or financial data; no retained images by default. Obtain affirmative user consent before each image upload (or explicit controlled preference). Do not upload silently.

Existing independent gateway client in experimental PR #412 is not an operational service. A secure gateway must be independently deployed, configured and tested. Without it, no internet-only AI can be claimed to work. Failure, no internet, or missing credential -> continue with Quick/Manual and retained photo; never secretly fall back to the old Supabase receipt-parse function.

Gateway JSON contract:
- vendor_name
- receipt_date (YYYY-MM-DD; null when unknown)
- vendor_invoice_number (string; preserve leading zeros)
- receipt_total, subtotal, tax/fees/surcharge only where actually identified
- items: position, description, sku, quantity, unit_price, total_amount
- extraction_source, review_flags, confidence/uncertainty fields

Review requires correction before applying suggestions. Existing local vendor/category matching remains on the phone; vendor is a separate field. Do not invent missing amounts, SKUs or tax. Printed receipt total already includes included taxes and fees; do not re-add a default vendor surcharge.

## Preserve old expense behavior

Expense Description: part descriptions joined by commas (up to ten distinct item descriptions), then invoice number, date, total, separated by em dashes. Vendor name only if item descriptions absent. SKUs stored in structured receipt items, never substituted into Description.

Verified saved-example fixtures:
- Worldpac 74966713 — 2026-10-27 — $191.35 — Brake Disc, Brake Pad Set, Brake Pad Sensor.
- AutoZone 04290190370 — 2026-10-24 — $131.30 — NGK Laser Iridium NGK Spark Plug, Engine Air Filter STP Air Filter.
- Peake BMW 603162 — 2026-10-23 — $26.12 — Connecting link, Grommet.

Reuse current financial expense and receipt detail/item schema; offline financial writer creates transaction + one original photo + extraction projection in durable local SQLite; Supabase background sync only after local commit. Never duplicate records or attachments. Preserve current employee permissions.

## Tests required before Android acceptance

1. Airplane Mode: Quick and Full Manual can attach photos, save local expense and survive app restart/device reboot; no attempted AI call.
2. Internet with Supabase intentionally unreachable or Force Offline: optional AI works through independent gateway, and local save works; Quick/Manual available without gateway.
3. Internet available and Supabase healthy: same independent AI endpoint and review; background sync only after local save.
4. Gateway errors/timeout/unauthorized: no duplicate expense/photo; retain original photo, permit manual continuation and preserve editable fields.
5. Real photos for Worldpac, AutoZone, Peake BMW; test dates, zero-prefixed invoice strings, items, part numbers, totals, description formatting, vendor matching, tax/surcharge, missing values.
6. Consent/privacy/permissions and local persistence across restart; verify only explicit photo uploads.
7. Isolated Android TEST APK with distinct package ID, version, signing and SHA256; physical Samsung acceptance before merging.

## Engineering steps

A. Start from a safe, current stable expense branch; keep existing Quick/Manual paths and local photo/financial writer. Avoid importing payroll/LAN/Gloria/Owner Delete work.
B. Implement independent authenticated gateway and client with secure credentials and user consent. Cannot call AI operational until gateway is actually deployed.
C. Replace the Supabase AI read flow in Expense Entry. Do NOT integrate the experimental on-device OCR as a required step. If internet/gateway is unavailable, manual and Quick paths remain first-class.
D. Implement reviewed structured receipt local persistence and separate background sync; test.
E. Deliver a separately installable TEST APK, verify end-to-end physical Samsung behavior, and promote only after acceptance.

PR #412 remains experimental and unmerged. Selectively reuse tested local persistence / review work only, not the buggy offline OCR workflow. The existing regular Briskers b2552 online scanner remains the **temporary working method** for the owner while the independent gateway is being deployed.
