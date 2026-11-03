# Briskers offline-first receipt OCR — isolated acceptance record

Issue: #411. Feature branch: \`feature/offline-receipt-ocr-independent-ai-20261102\`.
Draft PR: #412, targeting \`release/bugs26-afterwork-20261102\`.
**Do not merge into the shop build or install over Owner 2552 until physical acceptance.**

## Architecture and current behavior

1. The expense editor still captures/chooses a receipt in the existing Expense UI.
2. \`OnDeviceReceiptReader\` reads the original selected image with the
   bundled ML Kit Latin OCR (no network, Supabase, or external AI).
3. \`LocalReceiptParser\` extracts conservative suggestions: known locally cached
   vendor names, dates, invoice numbers (strings), explicit labeled totals, and
   line-item descriptions, SKUs, quantities, unit and line prices when they are
   recognizable together. Missing/ambiguous fields are blank/flagged.
4. A separate **Review receipt** sheet lets the operator edit all recognized
   fields and add/remove part lines. Dismissing it retains the attached photo
   but does not apply unreviewed fields.
5. The confirmed expense saves via \`OfflineFinancialWriteService\` even in Auto:
   SQLite financial summary/detail, receipt details/items projection, original
   staged photo and sync outbox. Server sync is separate and deferred.
6. The receipt total is treated as the printed final amount. Selecting a vendor
   does not add a default percentage again to a recognized printed total.
7. An optional independent HTTPS gateway client is present, with separate
   gateway-issued access token held in device secure storage. Each image upload
   requires explicit consent and the result requires a new Review confirmation.
   Cloud AI is NOT available until a separate gateway is deployed/configured and
   live integration is verified. No provider secret is embedded in the APK.
8. Test build only (\`BRISKERS_RECEIPT_TEST=true\`): the existing expense
   editor opens inside a synthetic isolated receipt TEST harness with its own
   Android package \`com.briskers.receipt_ocr_test\`, own local SQLite data and
   synthetic accounts, categories and known suppliers. All Supabase
   synchronization remains disabled. This is intentionally not the Owner app.

## Saved-example comparison

Fixtures are text transcriptions based on read-only previously verified
records, NOT independent OCR-accuracy benchmarks on actual vendor photos.

| Vendor | Invoice (string) | Date | Amount | Expected descriptions |
| --- | --- | --- | --- | --- |
| Worldpac | 74966713 | 2026-10-27 | $191.35 | Brake Disc, Brake Pad Set, Brake Pad Sensor |
| AutoZone | 04290190370 | 2026-10-24 | $131.30 | NGK Laser Iridium NGK Spark Plug, Engine Air Filter STP Air Filter |
| Peake BMW | 603162 | 2026-10-23 | $26.12 | Connecting link, Grommet |

Full descriptions must equal:

- \`Brake Disc, Brake Pad Set, Brake Pad Sensor — Inv. 74966713 — 10/27/26 — $191.35\`
- \`NGK Laser Iridium NGK Spark Plug, Engine Air Filter STP Air Filter — Inv. 04290190370 — 10/24/26 — $131.30\`
- \`Connecting link, Grommet — Inv. 603162 — 10/23/26 — $26.12\`

Structured item fields preserve descriptions separately from SKU strings. Never
claim AutoPak transaction fixtures were inspected.

## Automated tests

- \`test/offline_receipt_parser_test.dart\`: 7 fixtures/edge cases for
  vendor, invoice leading zeros, dates, explicit totals, SKU/qty/price math,
  missing/invalid data, formatting and 10-description limit.
- \`test/offline_receipt_persistence_test.dart\`: synthetic SQLite expense
  create, one original photo, 3 structured part items, one idempotent queued
  extraction after edit, close/reopen database, preserved unsynced expense.
- \`test/expense_receipt_entry_contract_test.dart\`: existing safe photo
  selection and expense editor contract.
- Workflow \`.github/workflows/receipt-isolated-test-apk.yml\`: tests first,
  creates a separate Android package, builds a debug-signed TEST APK, checks
  identity and signature, uploads artifact plus SHA256.

## Physical device acceptance (still required)

- Install the **separate Receipt TEST package**, not over b2552.
- In airplane mode: Scan Receipt, capture invoice, review and edit fields,
  save, close and reopen the TEST app; verify description, structured items,
  one original photo and preserved expense; ideally reboot the phone.
- Repeat with Wi-Fi on while Supabase remains blocked by TEST flag; ensure
  same scan/save behavior with no cloud-account dependencies.
- Compare real images from Worldpac, AutoZone and Peake BMW with above
  expected results. Identify any vendor layout-specific parsing misses.
- Test photo removal, retaking unclear scans, offline persistence and no
  duplicates; confirm that cloud upload never occurs without consent.
- Online independent AI gateway test requires a real authenticated gateway
  URL, tenant-scoped credentials and test endpoint; it is NOT simulated by
  calling Supabase.

## Pending design/acceptance considerations

- Multi-page/complex invoices and imperfect OCR may require manual review or
  targeted vendor-specific templates. Deterministic parsing is intentionally
  conservative; matching fixtures does not guarantee all photos are recognized.
- The local receipt-details and item equivalents are a SQLite-backed JSON
  projection in existing financial transaction detail, not new SQL tables;
  data is remapped and replayed to existing server receipt RPC only at sync.
- The online gateway is client-side plumbing only until an independent gateway
  is provisioned and end-to-end tested. Supabase receipt parsing remains as
  a legacy API method but is not used for new scanner recognition.
- Do not enable recurring schedules on scanned receipts until local recurring
  rules are supported; scanned expense commits stay local-first.
